# frozen_string_literal: true

module Prism
  module Ruby
    # pm_options_t, read from the keywords of a Prism call as the C
    # extension reads them (extension.c build_options_i), with its errors.
    # The messages of those errors are binary, as rb_raise makes them.
    class Options
      # pm_options_version_t
      VERSION_CRUBY_3_3 = 1
      VERSION_CRUBY_3_4 = 2
      VERSION_CRUBY_4_0 = 3
      VERSION_CRUBY_4_1 = 4
      VERSION_LATEST = VERSION_CRUBY_4_1

      # PM_OPTIONS_FROZEN_STRING_LITERAL_*
      FROZEN_STRING_LITERAL_DISABLED = -1
      FROZEN_STRING_LITERAL_UNSET = 0
      FROZEN_STRING_LITERAL_ENABLED = 1

      # PM_OPTIONS_COMMAND_LINE_*
      COMMAND_LINE = { "a" => 0x1, "e" => 0x2, "l" => 0x4, "n" => 0x8, "p" => 0x10, "x" => 0x20 }.freeze

      # The range of a C int.
      INT = -(2**31)..(2**31 - 1)

      # The range of a C long.
      LONG = -(2**63)..(2**63 - 1)

      # PM_OPTIONS_SCOPE_FORWARDING_*
      FORWARDING = { :* => 0x1, :** => 0x2, :& => 0x4, :"..." => 0x8 }.freeze

      # A scope an eval parses inside: local names as Strings, and what the
      # scope forwards.
      EvalScope = Struct.new(:locals, :forwarding)

      attr_reader :filepath, :line, :encoding, :frozen_string_literal, :command_line, :version, :scopes

      def initialize(filepath = nil, **keywords)
        @filepath = nil
        @line = 1
        @encoding = nil
        @encoding_locked = false
        @frozen_string_literal = FROZEN_STRING_LITERAL_UNSET
        @command_line = 0
        @version = 0
        @main_script = false
        @partial_script = false
        @freeze = false
        @scopes = []
        keywords.each { |key, value| read(key, value) }
        return if filepath.nil?

        @filepath = c_string(Options.check_type(filepath, String))
      end

      def encoding_locked? = @encoding_locked
      def main_script? = @main_script
      def partial_script? = @partial_script
      def freeze? = @freeze

      # Check_Type: the value, or the TypeError of one not of the type.
      def self.check_type(value, type, expected = type.name)
        raise TypeError, "wrong argument type #{value.class} (expected #{expected})".b unless value.is_a?(type)

        value
      end

      # A String as C reads it through its pointer: up to the first NUL.
      def self.c_string(value) = (at = value.byteindex("\0")) ? value.byteslice(0, at) : value

      private

      # build_options_i
      def read(key, value)
        case key
        when :filepath then @filepath = c_string(string(value)) unless value.nil?
        when :encoding
          if value == false
            @encoding_locked = true
          elsif !value.nil?
            @encoding = (value.is_a?(::Encoding) ? value : ::Encoding.find(value)).name
          end
        when :line then @line = int(value) unless value.nil?
        when :frozen_string_literal
          @frozen_string_literal = value ? FROZEN_STRING_LITERAL_ENABLED : FROZEN_STRING_LITERAL_DISABLED unless value.nil?
        when :version then @version = read_version(value) unless value.nil?
        when :scopes then @scopes = read_scopes(value) unless value.nil?
        when :command_line then @command_line = read_command_line(c_string(string(value))) unless value.nil?
        when :main_script then @main_script = value ? true : false unless value.nil?
        when :partial_script then @partial_script = value ? true : false unless value.nil?
        when :freeze then @freeze = value ? true : false unless value.nil?
        else raise ArgumentError, "unknown keyword: #{key}".b
        end
      end

      # check_string
      def string(value) = Options.check_type(value, String)

      def c_string(value) = Options.c_string(value)

      # NUM2INT: the value as a long (rb_num2long), then in an int's range.
      def int(value)
        long =
          if value.is_a?(Float)
            raise RangeError, "float #{format("%-.10g", value)} out of range of integer".b unless value.finite? && LONG.cover?(value.truncate)

            value.truncate
          else
            integer = Integer.try_convert(value) || raise(TypeError, "no implicit conversion of #{value.class} into Integer".b)
            raise RangeError, "bignum too big to convert into 'long'".b unless LONG.cover?(integer)

            integer
          end
        raise RangeError, "integer #{long} too #{long.negative? ? "small" : "big"} to convert to 'int'".b unless INT.cover?(long)

        long
      end

      def read_version(value)
        text = string(value)
        if text == "current"
          found = version_number(RUBY_VERSION.byteslice(0, 3))
          raise CurrentVersionError, RUBY_VERSION if found.nil?

          found
        else
          version_number(text) || raise(ArgumentError, "invalid version: #{value}".b)
        end
      end

      # pm_options_version_set
      def version_number(text)
        case text
        when "3.3" then VERSION_CRUBY_3_3
        when "3.4" then VERSION_CRUBY_3_4
        when "3.5", "4.0" then VERSION_CRUBY_4_0
        when "4.1" then VERSION_CRUBY_4_1
        when /\A3\.3\.\d*\z/ then VERSION_CRUBY_3_3
        when /\A3\.4\.\d*\z/ then VERSION_CRUBY_3_4
        when /\A(?:3\.5|4\.0)\.\d*\z/ then VERSION_CRUBY_4_0
        when /\A4\.1\.\d*\z/ then VERSION_CRUBY_4_1
        when "latest" then VERSION_LATEST
        end
      end

      def read_command_line(text)
        text.b.each_char.reduce(0) do |flags, char|
          flags | COMMAND_LINE.fetch(char) { raise ArgumentError, "invalid command line flag: '#{char}'".b }
        end
      end

      # build_options_scopes
      def read_scopes(value)
        Options.check_type(value, Array)

        value.map do |scope|
          locals, forwarding =
            case scope
            when Array then [scope, 0]
            when Prism::Scope then scope_parts(scope)
            else raise TypeError, "wrong argument type #{scope.class} (expected Array or Prism::Scope)".b
            end
          EvalScope.new(locals.map { |local| symbol(local).name }, forwarding)
        end
      end

      def scope_parts(scope)
        locals = scope.instance_variable_get(:@locals)
        Options.check_type(locals, Array)

        names = scope.instance_variable_get(:@forwarding)
        Options.check_type(names, Array)

        forwarding = names.reduce(0) do |flags, name|
          flags | FORWARDING.fetch(symbol(name)) { raise ArgumentError, "invalid forwarding value: #{name}".b }
        end
        [locals, forwarding]
      end

      def symbol(value) = Options.check_type(value, Symbol)
    end
  end
end
