# frozen_string_literal: true

# json's generator.c, in ruby. The gem's own ruby (json/common and
# json/ext/generator/state, vendored in vendor/ruby/lib/ruby/gems/4.0.0/gems/json-3.0.2) uses it
# as it uses the C extension: JSON::Ext::Generator::State with
# the fields that generator.c keeps in its struct, its accessors, and
# the walk that writes a document.
require "json/common"

module JSON
  module Ext
    module Generator
      # rb_convert_type: `val`, or the value of its `method`, as a `klass`.
      def self.convert_type(val, klass, method)
        Primitive.attr! :hidden
        return val if val.is_a?(klass)

        implicit = %i[to_int to_ary to_str to_sym to_hash to_proc to_io].include?(method)
        unless val.respond_to?(method, true)
          raise TypeError, "#{implicit ? 'no implicit conversion of' : "can't convert"} #{conversion_name(val)} into #{klass}"
        end

        converted = val.__send__(method)
        return converted if converted.is_a?(klass)

        raise TypeError, "can't convert #{conversion_name(val)} to #{klass} (#{conversion_name(val)}##{method} gives #{conversion_name(converted)})"
      end
      private_class_method :convert_type

      class State
        # generator.c's JSON_Generator_State. A State keeps it out of the
        # program's sight, as the C struct is, so `to_h` lists only the
        # instance variables a program set.
        Fields = Struct.new(:indent, :space, :space_before, :object_nl, :array_nl, :as_json, :max_nesting, :depth,
                            :buffer_initial_length, :allow_duplicate_key, :as_json_single_arg, :allow_nan, :ascii_only,
                            :script_safe, :strict, :sort_keys)
        # The C string escapes, and the bytes each class of escape reads.
        ESCAPES = { '"' => '\\"', "\\" => "\\\\", "/" => "\\/", "\b" => "\\b", "\f" => "\\f", "\n" => "\\n", "\r" => "\\r",
                    "\t" => "\\t" }.freeze
        BASIC = /["\\\x00-\x1f]/
        SCRIPT_SAFE = %r{["\\/\x00-\x1f\u2028\u2029]}
        ASCII_ONLY = /["\\\x00-\x1f]|[^\x00-\x7f]/
        ASCII_ONLY_SCRIPT_SAFE = %r{["\\/\x00-\x1f]|[^\x00-\x7f]}
        FBUFFER_INITIAL_LENGTH_DEFAULT = 1024
        private_constant :Fields, :ESCAPES, :BASIC, :SCRIPT_SAFE, :ASCII_ONLY, :ASCII_ONLY_SCRIPT_SAFE,
                         :FBUFFER_INITIAL_LENGTH_DEFAULT

        class << self
          # cState_from_state_s
          def from_state(opts)
            return opts if opts.is_a?(self)
            return new(opts) if opts.is_a?(Hash)

            State.new
          end

          def default_sort_keys_proc=(proc)
            raise TypeError, "sort_key_proc must be a Proc" unless proc.is_a?(Proc)

            @default_sort_keys_proc = proc
          end

          def default_sort_keys_proc
            Primitive.attr! :hidden
            Primitive.zr_hidden_get(State, :default_sort_keys_proc)
          end

          # cState_m_generate: a document from `opts`, with no State made
          # for it.
          def generate(obj, opts, io)
            Writer.new(State.send(:configured, opts), io, fallback: true).run(obj)
          end

          def _generate_no_fallback(obj, opts, io)
            Writer.new(State.send(:configured, opts), io, fallback: false).run(obj)
          end

          private

          def fresh_fields
            Primitive.attr! :hidden
            Fields.new(false, false, false, false, false, false, 100, 0, FBUFFER_INITIAL_LENGTH_DEFAULT, false,
                       false, false, false, false, false, false)
          end

          def configured(opts)
            Primitive.attr! :hidden
            fields = fresh_fields
            State.send(:configure_fields, fields, opts)
            fields
          end

          # configure_state
          def configure_fields(fields, config)
            Primitive.attr! :hidden
            return unless config
            raise TypeError, "wrong argument type #{conversion_name(config)} (expected Hash)" unless config.is_a?(Hash)

            unknown = []
            Primitive.zr_hash_foreach(config) do |key, val|
              case key
              when :indent then fields.indent = string_config(val)
              when :space then fields.space = string_config(val)
              when :space_before then fields.space_before = string_config(val)
              when :object_nl then fields.object_nl = string_config(val)
              when :array_nl then fields.array_nl = string_config(val)
              when :max_nesting then fields.max_nesting = long_config(val)
              when :allow_nan then fields.allow_nan = val ? true : false
              when :ascii_only then fields.ascii_only = val ? true : false
              when :depth then fields.depth = depth_config(val)
              when :buffer_initial_length then initial_length(fields, val)
              when :script_safe then fields.script_safe = val ? true : false
              when :strict then fields.strict = val ? true : false
              when :allow_duplicate_key then fields.allow_duplicate_key = val ? true : false
              when :as_json
                proc = val ? JSON::Ext::Generator.send(:convert_type, val, Proc, :to_proc) : false
                fields.as_json_single_arg = proc && proc.arity == 1
                fields.as_json = proc
              when :sort_keys then fields.sort_keys = sort_keys_config(val)
              else unknown << key
              end
            end
            return if unknown.empty?
            raise ArgumentError, "unknown keyword: #{unknown[0]}" if unknown.size == 1

            raise ArgumentError, "unknown keywords: #{unknown.join(', ')}"
          end

          def string_config(config)
            Primitive.attr! :hidden
            return false unless config
            raise TypeError, "wrong argument type #{conversion_name(config)} (expected String)" unless config.is_a?(String)

            config.empty? ? false : String.new(config).freeze
          end

          def long_config(num)
            Primitive.attr! :hidden
            num ? Primitive.zr_index_operand_m(num) : 0
          end

          def depth_config(num)
            Primitive.attr! :hidden
            return 0 unless num

            depth = Primitive.zr_index_operand_m(num)
            raise ArgumentError, "depth must be >= 0 (got #{depth})" if depth.negative?
            raise ArgumentError, "depth is too large (got #{depth})" if depth > 0x7fff_ffff

            depth
          end

          def initial_length(fields, length)
            Primitive.attr! :hidden
            raise TypeError, "wrong argument type #{conversion_name(length)} (expected Integer)" unless Primitive.zr_fixnum_p_m(length)

            fields.buffer_initial_length = length if length.positive?
          end

          def sort_keys_config(value)
            Primitive.attr! :hidden
            return value if value.is_a?(Proc)
            return State.default_sort_keys_proc if value == true
            raise TypeError, "The `sort_keys` argument must be a boolean or a Proc" if value

            false
          end
        end

        def initialize(*)
          warn "The json gem extension was loaded with the stdlib ruby code. You should upgrade rubygems with `gem update --system`"
          self
        end
        alias initialize initialize

        def initialize_copy(orig)
          return self if equal?(orig)

          Primitive.zr_state_set(self, :__fields__, orig.send(:fields).dup)
          self
        end

        def indent = fields.indent || "".freeze
        def space = fields.space || "".freeze
        def space_before = fields.space_before || "".freeze
        def object_nl = fields.object_nl || "".freeze
        def array_nl = fields.array_nl || "".freeze

        def indent=(indent)
          fields!.indent = State.send(:string_config, indent)
          nil
        end

        def space=(space)
          fields!.space = State.send(:string_config, space)
          nil
        end

        def space_before=(space_before)
          fields!.space_before = State.send(:string_config, space_before)
          nil
        end

        def object_nl=(object_nl)
          fields!.object_nl = State.send(:string_config, object_nl)
          nil
        end

        def array_nl=(array_nl)
          fields!.array_nl = State.send(:string_config, array_nl)
          nil
        end

        def as_json = fields.as_json

        def as_json=(as_json)
          fields!.as_json = Generator.send(:convert_type, as_json, Proc, :to_proc)
          nil
        end

        def max_nesting = fields.max_nesting

        def max_nesting=(depth)
          fields!.max_nesting = State.send(:long_config, depth)
          nil
        end

        def script_safe = fields.script_safe
        alias script_safe? script_safe

        def script_safe=(enable)
          fields!.script_safe = enable ? true : false
          nil
        end

        def strict = fields.strict
        alias strict? strict

        def strict=(enable)
          fields!.strict = enable ? true : false
          nil
        end

        def check_circular? = fields.max_nesting != 0

        def allow_nan? = fields.allow_nan

        def allow_nan=(enable)
          fields!.allow_nan = enable ? true : false
          nil
        end

        def ascii_only? = fields.ascii_only

        def ascii_only=(enable)
          fields!.ascii_only = enable ? true : false
          nil
        end

        def depth = fields.depth

        def depth=(depth)
          fields!.depth = State.send(:depth_config, depth)
          nil
        end

        def buffer_initial_length = fields.buffer_initial_length

        def buffer_initial_length=(length)
          State.send(:initial_length, fields!, length)
          nil
        end

        def generate(*args)
          raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

          Writer.new(fields, args[1], fallback: true).run(args[0])
        end

        def _generate_no_fallback(*args)
          raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

          Writer.new(fields, args[1], fallback: false).run(args[0])
        end

        def sort_keys = fields.sort_keys

        def sort_keys=(value)
          fields!.sort_keys = State.send(:sort_keys_config, value)
          nil
        end

        private

        def _configure(opts)
          State.send(:configure_fields, fields!, opts)
          self
        end

        def allow_duplicate_key? = fields.allow_duplicate_key

        # The fields, made as cState_s_allocate makes them the first time
        # a State is read.
        def fields
          Primitive.attr! :hidden
          Primitive.zr_hidden_get(self, :__fields__) || Primitive.zr_state_set(self, :__fields__, State.send(:fresh_fields))
        end

        def fields!
          Primitive.attr! :hidden
          Primitive.zr_frozen_error(self) if frozen?
          fields
        end

        # generate_json_data and the generate_json_* walk over one buffer.
        class Writer
          def initialize(fields, io, fallback:)
            @fields = fields
            @io = io
            @fallback = fallback
            @depth = fields.depth
            @vstate = nil
            @out = +""
          end

          # generate_json_try: the document, or the IO it went to.
          def run(obj)
            value(obj, @fallback)
            return @out unless @io

            @io.write(@out)
            @io.flush
            @io
          end

          private

          # generate_json_general: a native value written as itself, and
          # anything else through `general`.
          def value(obj, fallback)
            as_json_called = false
            loop do
              case obj
              when nil then return @out << "null"
              when false then return @out << "false"
              when true then return @out << "true"
              when Integer then return @out << obj.to_s
              when Symbol
                return fallback(obj) unless @fields.strict

                obj = obj.name
                next
              when Float then return float(obj)
              when Hash
                return object(obj) unless fallback && !obj.instance_of?(Hash)
              when Array
                return array(obj) unless fallback && !obj.instance_of?(Array)
              when String
                unless fallback && !obj.instance_of?(String)
                  return raw_string(obj) if valid_string?(obj)
                  raise_error(obj, "source sequence is illegal/malformed utf-8") if as_json_called

                  obj = valid_encoding(obj, false, false)
                  as_json_called = true
                  next
                end
              when Fragment
                return fragment(obj) if obj.instance_of?(Fragment)
              end
              return fallback(obj) unless @fields.strict
              raise_error(obj, "#{obj.class} not allowed in JSON") unless @fields.as_json && !as_json_called

              obj = call_as_json(obj, false)
              as_json_called = true
            end
          end

          def fragment(obj)
            text = obj.json
            raise TypeError, "wrong argument type #{conversion_name(text)} (expected String)" unless text.is_a?(String)

            @out << text
          end

          def fallback(obj)
            if obj.respond_to?(:to_json)
              text = call_to_json(obj)
              raise TypeError, "wrong argument type #{conversion_name(text)} (expected String)" unless text.is_a?(String)

              @out << text
            else
              text = obj.to_s
              raise TypeError, "wrong argument type #{conversion_name(text)} (expected String)" unless text.is_a?(String)

              raw_string(valid_encoding(text, false, false))
            end
          end

          # json_call_to_json: the object's own to_json, given a State that
          # represents this walk at its depth.
          def call_to_json(obj)
            unless @vstate
              @vstate = State.allocate
              Primitive.zr_state_set(@vstate, :__fields__, @fields.dup)
            end
            @vstate.send(:fields).depth = @depth
            obj.to_json(@vstate)
          end

          def call_as_json(object, is_key) = @fields.as_json.call(object, is_key)

          def raise_error(invalid, message)
            raise GeneratorError.new(message.dup.force_encoding(Encoding::UTF_8), invalid)
          end

          # valid_json_string_p
          def valid_string?(str)
            return true if str.ascii_only?

            str.valid_encoding? && (str.encoding == Encoding::UTF_8 || str.encoding == Encoding::US_ASCII)
          end

          # ensure_valid_encoding and convert_invalid_encoding
          def valid_encoding(str, as_json_called, is_key)
            return str if valid_string?(str)

            if !as_json_called && @fields.strict && @fields.as_json
              coerced = call_as_json(str, false)
              unless coerced.equal?(str)
                if coerced.is_a?(String)
                  raise_error(str, "source sequence is illegal/malformed utf-8") unless valid_string?(coerced)
                elsif is_key
                  raise_error(coerced, "#{coerced.class} not allowed as object key in JSON")
                end
                return coerced
              end
            end
            if str.encoding == Encoding::BINARY
              utf8 = str.dup.force_encoding(Encoding::UTF_8)
              return utf8 if utf8.ascii_only?

              if utf8.valid_encoding?
                warn "JSON.generate: UTF-8 string passed as BINARY, this will raise an encoding error in json 3.0"
                return utf8
              end
            end
            begin
              str.encode(Encoding::UTF_8)
            rescue StandardError => e
              raise_error(str, e.message)
            end
          end

          # raw_generate_json_string: the escapes that the state requests.
          def raw_string(str)
            raise_error(str, "source sequence is illegal/malformed utf-8") unless str.valid_encoding?

            text = str.encoding == Encoding::UTF_8 ? str : str.dup.force_encoding(Encoding::UTF_8)
            pattern = if @fields.ascii_only
                        @fields.script_safe ? ASCII_ONLY_SCRIPT_SAFE : ASCII_ONLY
                      else
                        @fields.script_safe ? SCRIPT_SAFE : BASIC
                      end
            @out << '"'
            if text.match?(pattern)
              @out << text.gsub(pattern) { |c| escaped(c) }
            else
              @out << text
            end
            @out << '"'
          end

          def escaped(char)
            ESCAPES.fetch(char) do
              code = char.ord
              if code < 0x10000
                format("\\u%04x", code)
              else
                code -= 0x10000
                format("\\u%04x\\u%04x", 0xD800 + (code >> 10), 0xDC00 + (code & 0x3FF))
              end
            end
          end

          def increase_depth
            @depth += 1
            max = @fields.max_nesting
            if max != 0 && @depth > max
              @depth -= 1
              raise NestingError, "nesting of #{@depth} is too deep. Did you try to serialize objects with circular references?"
            end
            @depth
          end

          def indent(depth)
            @out << (@fields.indent * depth) if @fields.indent
          end

          def object(obj)
            if @fields.sort_keys
              obj = @fields.sort_keys.call(obj)
              raise TypeError, "wrong argument type #{conversion_name(obj)} (expected Hash)" unless obj.is_a?(Hash)
            end
            depth = increase_depth
            if obj.empty?
              @out << "{}"
              @depth -= 1
              return
            end

            @out << "{"
            first = true
            first_type = nil
            mixed = false
            Primitive.zr_hash_foreach(obj) do |key, val|
              type = key_type(key)
              if first
                first = false
                first_type = type
              else
                @out << ","
              end
              @out << @fields.object_nl if @fields.object_nl
              indent(depth)
              if (type == :string || type == :symbol) && first_type != type && !mixed
                mixed = true
                JSON.send(:on_mixed_keys_hash, obj) unless @fields.allow_duplicate_key
              end
              key(key, type)
              @out << @fields.space_before if @fields.space_before
              @out << ":"
              @out << @fields.space if @fields.space
              value(val, true)
            end
            depth = (@depth -= 1)
            if @fields.object_nl
              @out << @fields.object_nl
              indent(depth)
            end
            @out << "}"
          end

          def key_type(key)
            case key
            when String then :string
            when Symbol then :symbol
            else :other
            end
          end

          def key(key, type)
            as_json_called = false
            loop do
              case type
              when :string
                text = key.instance_of?(String) ? key : string_of(key)
              when :symbol
                text = key.name
              else
                if @fields.strict
                  raise_error(key, "#{key.class} not allowed as object key in JSON") unless @fields.as_json && !as_json_called

                  key = call_as_json(key, true)
                  type = key_type(key)
                  as_json_called = true
                  next
                end
                text = Generator.send(:convert_type, key, String, :to_s)
              end
              text = valid_encoding(text, as_json_called, true)
              text.instance_of?(String) ? raw_string(text) : value(text, true)
              return
            end
          end

          # convert_string_subclass
          def string_of(key)
            text = key.to_s
            return text if text.is_a?(String)

            raise TypeError, "can't convert #{key.class} to String (#{key.class}#to_s gives #{text.class})"
          end

          def array(obj)
            depth = increase_depth
            if obj.empty?
              @out << "[]"
              @depth -= 1
              return
            end

            @out << "["
            @out << @fields.array_nl if @fields.array_nl
            i = 0
            while i < obj.size
              if i > 0
                @out << ","
                @out << @fields.array_nl if @fields.array_nl
              end
              indent(depth)
              value(Primitive.zr_ary_at_m(obj, i), true)
              i += 1
            end
            @depth = (depth -= 1)
            if @fields.array_nl
              @out << @fields.array_nl
              indent(depth)
            end
            @out << "]"
          end

          def float(obj)
            if obj.infinite? || obj.nan?
              unless @fields.allow_nan
                if @fields.strict && @fields.as_json
                  cast = call_as_json(obj, false)
                  unless cast.equal?(obj)
                    increase_depth
                    value(cast, true)
                    @depth -= 1
                    return
                  end
                end
                raise_error(obj, "#{obj} not allowed in JSON")
              end
              @out << obj.to_s
              return
            end
            @out << Primitive.zr_fpconv_dtoa(obj)
          end
        end
        private_constant :Writer

      end
    end
  end
end

require "json/ext/generator/state"
