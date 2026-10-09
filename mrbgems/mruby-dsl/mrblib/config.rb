# Declarative configuration objects. Macros own behavior and introspection together.
# This layer is market-neutral and does not register configuration classes as languages.
module JohnnyBtDSL
  class Config
    UNSET = Object.new.freeze

    class << self
      def inherited(child)
        super
        child.instance_variable_set(:@definitions, {})
        child.instance_variable_set(:@checks, [])
      end

      def definitions
        local = @definitions ||= {}
        parent = superclass
        if parent.respond_to?(:definitions)
          parent.definitions.merge(local)
        else
          local
        end
      end

      def checks
        local = @checks ||= []
        parent = superclass
        parent.respond_to?(:checks) ? parent.checks + local : local
      end

      def describe(text)
        @description = text.to_s
      end

      def description
        return @description if instance_variable_defined?(:@description)
        superclass.respond_to?(:description) ? superclass.description : ""
      end

      def open(value = true)
        @open = !!value
      end

      def open?
        return !!@open if instance_variable_defined?(:@open)
        superclass.respond_to?(:open?) ? superclass.open? : false
      end

      def copy(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), result| result[key] = copy(item) }
        when Array
          value.map { |item| copy(item) }
        when String
          value.dup
        else
          value
        end
      end

      def location(frame)
        path, line = JohnnyBtDSL::Base.place_of(frame)
        {"path" => path.to_s, "line" => line || 1}
      end

      def type_name(type)
        return type.map { |item| type_name(item) }.join("|") if type.is_a?(Array)
        return "string" if type == String
        return "integer" if type == Integer
        return "number" if type == Numeric
        return "float" if type == Float
        return "array" if type == Array
        return "hash" if type == Hash
        type.to_s
      end

      def definition(name, kind:, type: :any, doc:, required: false, default: UNSET,
                     nullable: false, min: nil, max: nil, enum: nil, positional: false,
                     impact: "", invariants: [], source: nil)
        raise ArgumentError, "A configuration definition requires documentation" if doc.to_s.empty?
        known = ["any", "string", "symbol", "integer", "number", "float", "boolean", "array", "hash", "self"]
        names = type_name(type).split("|")
        unless names.all? { |item| known.include?(item) || (type.is_a?(Class) && type <= Config) }
          raise ArgumentError, "Unknown configuration type: #{type_name(type)}"
        end
        spec = {
          "name" => name.to_s, "kind" => kind.to_s, "type" => type_name(type),
          "description" => doc.to_s, "required" => !!required,
          "has_default" => !default.equal?(UNSET), "nullable" => !!nullable,
          "positional" => !!positional, "impact" => impact.to_s,
          "invariants" => invariants.map(&:to_s), "source" => source || location(caller[1]),
          "constraints" => {},
        }
        spec["default"] = copy(default) unless default.equal?(UNSET)
        spec["constraints"]["min"] = min unless min.nil?
        spec["constraints"]["max"] = max unless max.nil?
        spec["constraints"]["enum"] = copy(enum) unless enum.nil?
        validate_value(spec, default) unless default.equal?(UNSET)
        spec
      end

      def install(spec, override)
        name = spec["name"]
        reserved = Config.instance_methods(false) + Config.private_instance_methods(false)
        reserved += [:class, :send, :instance_eval, :instance_exec, :is_a?, :respond_to?, :object_id]
        if reserved.any? { |method| method.to_s == name }
          raise ArgumentError, "#{name} is reserved by the configuration runtime"
        end
        if definitions.key?(name) && !override
          raise ArgumentError, "#{name} is already declared; use override: true"
        end
        @definitions ||= {}
        @definitions[name] = spec
      end

      def field(name, override: false, **options)
        spec = definition(name, kind: :field, source: location(caller.first), **options)
        install(spec, override)
        define_method(name) do |*values|
          raise ArgumentError, "#{name} requires one value" if values.length > 1
          return self[name] if values.empty?
          self[name] = values.first
          self
        end
        define_method("#{name}=") { |value| self[name] = value }
        spec
      end

      def relation(name, kind, of, item, override, options, source)
        unless of.is_a?(Class) && of <= Config
          raise ArgumentError, "Nested configuration types must inherit JohnnyBtDSL::Config"
        end
        spec = definition(name, kind: kind, type: :any, source: source, **options)
        spec["type"] = kind == :many ? "array" : of.name.to_s
        spec["block"] = of.name.to_s
        spec["item"] = item.to_s if item
        spec["_target"] = of
        install(spec, override)
        define_method(name) do |*values, &body|
          if body
            raise ArgumentError, "#{name} takes a block or a value, not both" unless values.empty?
            if kind == :one
              child = self[name] || of.new
              child.instance_eval(&body)
              self[name] = child
              child
            else
              rows = self[name] || []
              collector = Collection.new(of, item, rows)
              collector.instance_eval(&body)
              self[name] = rows
              collector
            end
          elsif values.empty?
            self[name]
          elsif values.length == 1
            self[name] = values.first
            self
          else
            raise ArgumentError, "#{name} requires one value"
          end
        end
        spec
      end

      def one(name, of:, override: false, **options)
        relation(name, :one, of, nil, override, options, location(caller.first))
      end

      def many(name, of:, item:, override: false, **options)
        relation(name, :many, of, item, override, options, location(caller.first))
      end

      def parameter(spec)
        options = spec.each_with_object({}) { |(key, value), out| out[key.to_sym] = value }
        name = options.delete(:name)
        raise ArgumentError, "A word parameter requires a name" unless name
        options[:required] = true unless options.key?(:required) || options.key?(:default)
        definition(name, kind: :parameter, **options)
      end

      # With a block, define implementation and metadata together. Without one,
      # bind and validate a method already defined in this same class.
      def word(name, doc:, arguments: [], keywords: [], returns: :any, block: nil,
               block_required: false, open_keywords: false, impact: "", invariants: [],
               override: false, &implementation)
        spec = definition(name, kind: :word, doc: doc, impact: impact, invariants: invariants,
                          source: location(caller.first))
        spec["arguments"] = arguments.map { |item| parameter(item) }
        spec["keywords"] = keywords.map { |item| parameter(item) }
        spec["returns"] = type_name(returns)
        spec["block"] = block.name.to_s if block
        spec["block_required"] = !!block_required
        spec["open_keywords"] = !!open_keywords
        spec["_target"] = block if block
        spec["_return_target"] = returns if returns.is_a?(Class) && returns <= Config
        install(spec, override)
        # Bind the original method directly. The pinned mruby cannot safely
        # mark an alias private on a class with prepended modules.
        define_method(name, &implementation) if implementation
        original = instance_method(name)
        owner = self
        define_method(name) do |*values, **named, &body|
          owner.validate_call(spec, values, named, body)
          values, named = owner.apply_defaults(spec, values, named) if implementation
          original.bind(self).call(*values, **named, &body)
        end
        spec
      end

      def validates(name, fields: [], doc:, &predicate)
        raise ArgumentError, "Custom validation requires a block and documentation" if !predicate || doc.to_s.empty?
        @checks ||= []
        @checks << {
          "name" => name.to_s, "fields" => fields.map(&:to_s),
          "description" => doc.to_s, "runtime_only" => true,
          "source" => location(caller.first), "_predicate" => predicate,
        }
      end

      def positional_fields
        definitions.values.select { |spec| spec["positional"] && spec["kind"] == "field" }
      end

      def validate_call(spec, values, named, body)
        arguments = spec["arguments"] || []
        raise ArgumentError, "#{spec['name']} received too many positional arguments" if values.length > arguments.length
        arguments.each_with_index do |parameter, index|
          if index < values.length
            validate_value(parameter, values[index])
          elsif parameter["required"] && !parameter["has_default"]
            raise ArgumentError, "#{spec['name']} requires #{parameter['name']}"
          end
        end
        keywords = spec["keywords"] || []
        named.each do |name, value|
          parameter = keywords.find { |item| item["name"] == name.to_s }
          if parameter
            validate_value(parameter, value)
          elsif !spec["open_keywords"]
            raise ArgumentError, "#{spec['name']} has no keyword #{name}"
          end
        end
        keywords.each do |parameter|
          present = named.keys.any? { |name| name.to_s == parameter["name"] }
          if !present && parameter["required"] && !parameter["has_default"]
            raise ArgumentError, "#{spec['name']} requires keyword #{parameter['name']}"
          end
        end
        raise ArgumentError, "#{spec['name']} requires a block" if spec["block_required"] && !body
        raise ArgumentError, "#{spec['name']} does not accept a block" if body && !spec["block"]
      end

      def apply_defaults(spec, values, named)
        values = values.dup
        named = named.dup
        (spec["arguments"] || []).each_with_index do |parameter, index|
          if index >= values.length && parameter["has_default"]
            values[index] = copy(parameter["default"])
          end
        end
        (spec["keywords"] || []).each do |parameter|
          present = named.keys.any? { |name| name.to_s == parameter["name"] }
          named[parameter["name"].to_sym] = copy(parameter["default"]) if !present && parameter["has_default"]
        end
        [values, named]
      end

      def numeric(value)
        if value.is_a?(Hash) && value.keys == ["$jbt.float64"] && value["$jbt.float64"].is_a?(String)
          JSON.parse(value["$jbt.float64"])
        else
          value
        end
      end

      def matches?(type, value)
        case type
        when "any" then true
        when "string" then value.is_a?(String)
        when "symbol" then value.is_a?(Symbol)
        when "integer" then value.is_a?(Integer)
        when "number" then numeric(value).is_a?(Numeric)
        when "float" then value.is_a?(Float)
        when "boolean" then value == true || value == false
        when "array" then value.is_a?(Array)
        when "hash" then value.is_a?(Hash)
        else false
        end
      end

      def validate_value(spec, value)
        return value if value.nil? && spec["nullable"]
        valid = spec["type"].split("|").any? { |type| matches?(type, value) }
        raise ArgumentError, "#{spec['name']} requires #{spec['type']}" unless valid
        number = numeric(value)
        if number.is_a?(Float) && !number.finite?
          raise ArgumentError, "#{spec['name']} must be finite"
        end
        constraints = spec["constraints"] || {}
        if constraints.key?("min") && (!number.is_a?(Numeric) || number < constraints["min"])
          raise ArgumentError, "#{spec['name']} must be at least #{constraints['min']}"
        end
        if constraints.key?("max") && (!number.is_a?(Numeric) || number > constraints["max"])
          raise ArgumentError, "#{spec['name']} must be at most #{constraints['max']}"
        end
        if constraints.key?("enum") && !constraints["enum"].include?(value)
          raise ArgumentError, "#{spec['name']} is not an allowed value"
        end
        value
      end

      def public_definition(spec)
        copy(spec.reject { |key, _| key.start_with?("_") })
      end

      def schema
        {
          "name" => name.to_s, "description" => description, "open" => open?,
          "fields" => definitions.values.map { |spec| public_definition(spec) },
          "validations" => checks.map { |check| public_definition(check) },
        }
      end

      def documents(seen = {})
        return [] if seen.key?(name.to_s)
        seen[name.to_s] = true
        result = [schema]
        definitions.values.each do |spec|
          [spec["_target"], spec["_return_target"]].compact.each do |target|
            result.concat(target.documents(seen))
          end
        end
        result
      end
    end

    def initialize(*values, **named)
      positional = self.class.positional_fields
      raise ArgumentError, "Too many positional configuration values" if values.length > positional.length
      values.each_with_index { |value, index| self[positional[index]["name"]] = value }
      named.each { |name, value| self[name] = value }
    end

    def explicit_values
      @explicit_values ||= {}
    end

    def [](name)
      key = name.to_s
      return explicit_values[key] if explicit_values.key?(key)
      spec = self.class.definitions[key]
      if spec && spec["has_default"]
        @default_values ||= {}
        @default_values[key] = self.class.copy(spec["default"]) unless @default_values.key?(key)
        @default_values[key]
      end
    end

    def []=(name, value)
      key = name.to_s
      spec = self.class.definitions[key]
      if !spec && !self.class.open?
        raise ArgumentError, "Unknown configuration field #{key}"
      end
      if spec && ["one", "many"].include?(spec["kind"])
        if value.nil? && spec["nullable"]
          explicit_values[key] = nil
          return value
        end
        target = spec["_target"]
        convert = lambda do |item|
          if item.is_a?(target)
            item
          elsif item.is_a?(Hash)
            target.new(**item)
          else
            raise ArgumentError, "#{key} requires #{target.name}"
          end
        end
        if spec["kind"] == "many"
          raise ArgumentError, "#{key} requires an array" unless value.is_a?(Array)
          value = value.map { |item| convert.call(item) }
        else
          value = convert.call(value)
        end
      elsif spec
        self.class.validate_value(spec, value)
      end
      explicit_values[key] = value
    end

    def provided?(name)
      explicit_values.key?(name.to_s)
    end

    def validate!
      unless self.class.open?
        unknown = explicit_values.keys.reject { |name| self.class.definitions.key?(name) }
        raise ArgumentError, "Unknown configuration fields: #{unknown.join(', ')}" unless unknown.empty?
      end
      self.class.definitions.each do |name, spec|
        next if spec["kind"] == "word"
        if !provided?(name) && !spec["has_default"]
          raise ArgumentError, "Missing required field #{name}" if spec["required"]
          next
        end
        value = self[name]
        if value.is_a?(Config)
          value.validate!
        elsif spec["kind"] == "many" && value
          value.each(&:validate!)
        else
          self.class.validate_value(spec, value)
        end
      end
      self.class.checks.each { |check| instance_exec(&check["_predicate"]) }
      self
    end

    def serialize(value, include_defaults)
      case value
      when Config then value.to_h(include_defaults: include_defaults)
      when Array then value.map { |item| serialize(item, include_defaults) }
      when Hash then value.each_with_object({}) { |(key, item), result| result[key] = serialize(item, include_defaults) }
      when String then value.dup
      else value
      end
    end

    def to_h(include_defaults: false)
      values = explicit_values.dup
      if include_defaults
        self.class.definitions.each do |name, spec|
          values[name] = self[name] if spec["has_default"] && !values.key?(name)
        end
      end
      values.each_with_object({}) { |(name, value), result| result[name] = serialize(value, include_defaults) }
    end

    def method_missing(name, *values, **named, &body)
      if self.class.open? && values.length == 1 && named.empty? && !body
        self[name] = values.first
        self
      else
        raise ArgumentError, "Unknown configuration word #{name}"
      end
    end

    class Collection
      def initialize(target, item, rows)
        @target, @item, @rows = target, item.to_s, rows
      end

      def method_missing(name, *values, **named, &body)
        raise ArgumentError, "Unknown collection word #{name}; expected #{@item}" unless name.to_s == @item
        child = @target.new(*values, **named)
        child.instance_eval(&body) if body
        @rows << child
        child
      end
    end
  end
end
