# frozen_string_literal: true
# shareable_constant_value: literal

module Prism
  module Ruby
    # Prism::StringQuery's native half (extension.c's string_query_*, over
    # prism.c's pm_string_query_*): whether a String is a local variable,
    # constant or method name in its own encoding.
    module StringQuery
      # The operator method names, by length.
      OPERATORS = %w[& ` ! ^ > < - % | + / * ~ != !~ [] == =~ >= >> <= << ** === <=> []=].freeze

      module_function

      # pm_string_query_local
      def local?(string) = slice_type(string) == :local

      # pm_string_query_constant
      def constant?(string) = slice_type(string) == :constant

      # pm_string_query_method_name
      def method_name?(string)
        case slice_type(string)
        when :local
          # A numbered parameter is not a method name.
          bytes = string.b
          bytes.bytesize != 2 || bytes.getbyte(0) != 0x5F || bytes.getbyte(1) == 0x30 || !bytes.getbyte(1).between?(0x30, 0x39)
        when :constant, :method_name then true
        else OPERATORS.include?(string.b)
        end
      end

      # pm_slice_type: :local or :constant for an identifier, by its first
      # character; :method_name for one ending in !, ? or =; else :none.
      def slice_type(string)
        Options.check_type(string, String)
        encoding = Encodings.find(string.encoding.name)
        raise ArgumentError, "Invalid or non ascii-compatible encoding".b if encoding.nil?

        source = string.b
        length = source.bytesize
        return :none if length == 0

        width = identifier_start(encoding, source, 0, length)
        return :none if width == 0

        type = encoding.isupper_char(source, 0, length) ? :constant : :local
        cursor = width
        while cursor < length
          width = identifier_part(encoding, source, cursor, length - cursor)
          break if width == 0

          cursor += width
        end

        # A !, ? or = may end a method name.
        if [0x21, 0x3F, 0x3D].include?(source.getbyte(cursor))
          cursor += 1
          type = :method_name
        end
        cursor == length ? type : :none
      end

      # The width of a character that may start an identifier: a letter, an
      # underscore, or any multibyte character.
      def identifier_start(encoding, source, at, length)
        width = encoding.alpha_char(source, at, length)
        return width if width != 0
        return 1 if source.getbyte(at) == 0x5F
        return encoding.char_width(source, at, length) if source.getbyte(at) >= 0x80

        0
      end

      # The width of a character that may continue an identifier: also a
      # digit.
      def identifier_part(encoding, source, at, length)
        width = encoding.alnum_char(source, at, length)
        return width if width != 0
        return 1 if source.getbyte(at) == 0x5F
        return encoding.char_width(source, at, length) if source.getbyte(at) >= 0x80

        0
      end
    end
  end
end
