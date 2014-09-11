module SugarCRM; class Response

    module ATTR
      MODULE_NAME       = 'module_name'
      NAME_VALUE_LIST   = 'name_value_list'
      NAME              = 'name'
      RECORDS           = 'records'
      RELATIONSHIP_LIST = 'relationship_list'
      ENTRY_LIST        = 'entry_list'
    end

    class << self
      # This class handles the response from the server.
      # It tries to convert the response into an object such as User
      # or an object collection.  If it fails, it just returns the response hash
      def handle(json, session, opts={})
        r = new(json, session, opts)
        begin
          return r.to_obj
        rescue UninitializedModule => e
          raise e
        rescue InvalidAttribute => e
          raise e
        rescue InvalidAttributeType => e
          raise e
        rescue => e
          if session.connection.debug?
            puts "Failed to process JSON:"
            pp json
          end
          raise e
        end
      end
    end

    attr :response, false

    attr_reader :namespace, :relationship_names

    def initialize(json, session, opts={})
      @options  = { :always_return_array => false }.merge! opts
      @response = json
      @response = json.with_indifferent_access if json.is_a? Hash
      @session = session
    end

    # Tries to instantiate and return an object with the values
    # populated from the response
    def to_obj
      # If this is not a "entry_list" response, just return
      return response unless response && response[ATTR::ENTRY_LIST]
      @namespace = @session.namespace_const
      @relationship_names = (@options[:link_fields] || []).map { |link_field| link_field[:name].to_s }

      objects = @response[ATTR::ENTRY_LIST].each.with_index.inject([]) do |objects, (record, idx)|
        _module    = record[ATTR::MODULE_NAME].classify
        attributes = record[ATTR::NAME_VALUE_LIST] ? flatten(record[ATTR::NAME_VALUE_LIST]) : {}

        assign_to(objects, _module, attributes)
        build_relationships(objects[idx], idx)

        objects
      end

      # If we only have one result, just return the object
      if objects.length == 1 && !@options[:always_return_array]
        return objects[0]
      else
        return objects
      end
    end

    def assign_to(collection, _module, attributes)
      if has_valid_environment_for?(_module, attributes)
        collection << @namespace.const_get(_module).new(attributes)
      end
      collection
    end

    def has_valid_environment_for?(_module, attributes)
      if @namespace.const_get(_module)
        if attributes.length == 0
          raise AttributeParsingError, "response contains objects without attributes!"
        end
        return true
      else
        raise InvalidModule, "#{_module} does not exist, or is not accessible"
      end
      false
    end

    # Takes a hash like { "first_name" => {"name" => "first_name", "value" => "John"}}
    # And flattens it into {"first_name" => "John"}
    def flatten(list)
      raise ArgumentError, list[0]['value'] if list[0] && list[0]['name'] == 'warning'
      raise ArgumentError, 'method parameter must respond to #each_pair' unless list.respond_to? :each_pair

      list.each_pair.inject({}) do |flat_list, (k, v)|
        flat_list[k.to_sym] = v["value"]
        flat_list
      end
    end

    def get_relationship_hash(name, idx)
      relationships = response[ATTR::RELATIONSHIP_LIST][idx] || []
      hash = relationships.find { |relationship_hash| relationship_hash[ATTR::NAME] == name }
      hash || {ATTR::RECORDS => []}
    end

    def build_relationships(object, idx)
      relationship_names.each do |relationship_name|
        relationship_hash = get_relationship_hash(relationship_name, idx)
        _module = relationship_name.capitalize.classify

        records = relationship_hash[ATTR::RECORDS].inject([]) do |records, record|
          attributes = record ? flatten(record) : {}
          assign_to(records, _module, attributes)
        end

        association = AssociationCollection.new(object, relationship_name)
        association.set_new_collection(records)
        object.association_cache[relationship_name] = association
      end
    end
end; end
