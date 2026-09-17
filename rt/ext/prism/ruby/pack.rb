# frozen_string_literal: true

module Prism
  module Ruby
    # Prism::Pack.parse's native half: api_pack.c over pack.c, which reads a
    # template of Array#pack or String#unpack into its directives.
    module Pack
      # What each directive letter reads as: its type, signedness,
      # endianness and size.
      DIRECTIVES = {
        "C" => %i[INTEGER UNSIGNED AGNOSTIC_ENDIAN SIZE_8],
        "S" => %i[INTEGER UNSIGNED NATIVE_ENDIAN SIZE_16],
        "L" => %i[INTEGER UNSIGNED NATIVE_ENDIAN SIZE_32],
        "Q" => %i[INTEGER UNSIGNED NATIVE_ENDIAN SIZE_64],
        "J" => %i[INTEGER UNSIGNED NATIVE_ENDIAN SIZE_P],
        "c" => %i[INTEGER SIGNED AGNOSTIC_ENDIAN SIZE_8],
        "s" => %i[INTEGER SIGNED NATIVE_ENDIAN SIZE_16],
        "l" => %i[INTEGER SIGNED NATIVE_ENDIAN SIZE_32],
        "q" => %i[INTEGER SIGNED NATIVE_ENDIAN SIZE_64],
        "j" => %i[INTEGER SIGNED NATIVE_ENDIAN SIZE_P],
        "I" => %i[INTEGER UNSIGNED NATIVE_ENDIAN SIZE_INT],
        "i" => %i[INTEGER SIGNED NATIVE_ENDIAN SIZE_INT],
        "n" => %i[INTEGER UNSIGNED BIG_ENDIAN SIZE_16],
        "N" => %i[INTEGER UNSIGNED BIG_ENDIAN SIZE_32],
        "v" => %i[INTEGER UNSIGNED LITTLE_ENDIAN SIZE_16],
        "V" => %i[INTEGER UNSIGNED LITTLE_ENDIAN SIZE_32],
        "U" => %i[UTF8 SIGNED_NA ENDIAN_NA SIZE_NA],
        "w" => %i[BER SIGNED_NA ENDIAN_NA SIZE_NA],
        "D" => %i[FLOAT SIGNED_NA NATIVE_ENDIAN SIZE_64],
        "d" => %i[FLOAT SIGNED_NA NATIVE_ENDIAN SIZE_64],
        "F" => %i[FLOAT SIGNED_NA NATIVE_ENDIAN SIZE_32],
        "f" => %i[FLOAT SIGNED_NA NATIVE_ENDIAN SIZE_32],
        "E" => %i[FLOAT SIGNED_NA LITTLE_ENDIAN SIZE_64],
        "e" => %i[FLOAT SIGNED_NA LITTLE_ENDIAN SIZE_32],
        "G" => %i[FLOAT SIGNED_NA BIG_ENDIAN SIZE_64],
        "g" => %i[FLOAT SIGNED_NA BIG_ENDIAN SIZE_32],
        "A" => %i[STRING_SPACE_PADDED SIGNED_NA ENDIAN_NA SIZE_NA],
        "a" => %i[STRING_NULL_PADDED SIGNED_NA ENDIAN_NA SIZE_NA],
        "Z" => %i[STRING_NULL_TERMINATED SIGNED_NA ENDIAN_NA SIZE_NA],
        "B" => %i[STRING_MSB SIGNED_NA ENDIAN_NA SIZE_NA],
        "b" => %i[STRING_LSB SIGNED_NA ENDIAN_NA SIZE_NA],
        "H" => %i[STRING_HEX_HIGH SIGNED_NA ENDIAN_NA SIZE_NA],
        "h" => %i[STRING_HEX_LOW SIGNED_NA ENDIAN_NA SIZE_NA],
        "u" => %i[STRING_UU SIGNED_NA ENDIAN_NA SIZE_NA],
        "M" => %i[STRING_MIME SIGNED_NA ENDIAN_NA SIZE_NA],
        "m" => %i[STRING_BASE64 SIGNED_NA ENDIAN_NA SIZE_NA],
        "P" => %i[STRING_FIXED SIGNED_NA ENDIAN_NA SIZE_NA],
        "p" => %i[STRING_POINTER SIGNED_NA ENDIAN_NA SIZE_NA],
        "@" => %i[MOVE SIGNED_NA ENDIAN_NA SIZE_NA],
        "X" => %i[BACK SIGNED_NA ENDIAN_NA SIZE_NA],
        "x" => %i[NULL SIGNED_NA ENDIAN_NA SIZE_NA]
      }.freeze

      # The integer directives whose size a ! or _ cannot change.
      FIXED_SIZE = %w[n N v V].freeze

      # The native size a ! or _ gives each fixed size.
      NATIVE_SIZES = { SIZE_16: :SIZE_SHORT, SIZE_32: :SIZE_LONG, SIZE_64: :SIZE_LONG_LONG }.freeze

      # A directive as pm_pack_parse reads it.
      Directive = Struct.new(:type, :signed, :endian, :size, :length_type, :length)

      UINT64_MAX = 2**64 - 1

      module_function

      # pack_parse: the template's directives and the encoding of what
      # packing it makes (nil for an empty template).
      def parse(version, variant, format)
        raise ArgumentError, "invalid version".b unless version == :v3_2_0
        raise ArgumentError, "invalid variant".b unless %i[pack unpack].include?(variant)

        bytes = string_value(format).b
        cursor = 0
        encoding = nil
        directives = []

        while cursor < bytes.bytesize
          start = cursor
          encoding ||= :US_ASCII
          directive, cursor, encoding = directive(variant, bytes, cursor, encoding)
          directives << Prism::Pack::Directive.new(version, variant, bytes.byteslice(start, cursor - start).force_encoding(::Encoding::US_ASCII),
                                                    *directive.to_a)
        end

        Prism::Pack::Format.new(directives, encoding && ::Encoding.const_get(encoding))
      end

      # StringValue
      def string_value(value)
        String.try_convert(value) || raise(TypeError, "no implicit conversion of #{value.nil? || value == true || value == false ? value.inspect : value.class} into String".b)
      end

      # pm_pack_parse: the directive at `cursor`, the cursor past it, and
      # the encoding after it.
      def directive(variant, bytes, cursor, encoding)
        letter = bytes.byteslice(cursor, 1)
        cursor += 1

        case letter
        when " ", "\t", "\n", "\v", "\f", "\r"
          return [Directive.new(:SPACE, :SIGNED_NA, :ENDIAN_NA, :SIZE_NA, :LENGTH_NA, 0), cursor, encoding]
        when "#"
          cursor += 1 while cursor < bytes.bytesize && bytes.getbyte(cursor) != 0x0A
          return [Directive.new(:COMMENT, :SIGNED_NA, :ENDIAN_NA, :SIZE_NA, :LENGTH_NA, 0), cursor, encoding]
        end

        type, signed, endian, size = DIRECTIVES.fetch(letter) { raise ArgumentError, "unsupported directive".b }
        directive = Directive.new(type, signed, endian, size, :LENGTH_FIXED, 1)
        cursor = modifiers(directive, bytes, cursor, !FIXED_SIZE.include?(letter))
        directive.length = 0 if variant == :unpack && type == :MOVE
        cursor = count(directive, variant, bytes, cursor)

        encoding =
          case type
          when :UTF8 then encoding == :US_ASCII ? :UTF_8 : encoding
          when :STRING_MIME, :STRING_BASE64, :STRING_UU then encoding
          else :BINARY
          end
        [directive, cursor, encoding]
      end

      # The modifiers after a directive: `!` or `_` for a native size, `<`
      # or `>` for an endianness.
      def modifiers(directive, bytes, cursor, size_changes)
        explicit_endian = false
        while cursor < bytes.bytesize
          case bytes.getbyte(cursor)
          when 0x5F, 0x21 # _ !
            cursor += 1
            raise RangeError, "bang not allowed".b unless directive.type == :INTEGER && size_changes

            case directive.size
            when :SIZE_SHORT, :SIZE_INT, :SIZE_LONG, :SIZE_LONG_LONG, :SIZE_P then nil
            when :SIZE_16, :SIZE_32, :SIZE_64 then directive.size = NATIVE_SIZES.fetch(directive.size)
            else raise RangeError, "bang not allowed".b
            end
          when 0x3C, 0x3E # < >
            cursor += 1
            raise RangeError, "double endian".b if explicit_endian

            directive.endian = bytes.getbyte(cursor - 1) == 0x3C ? :LITTLE_ENDIAN : :BIG_ENDIAN
            explicit_endian = true
          else
            break
          end
        end
        cursor
      end

      # The count after a directive: `*` or decimal digits.
      def count(directive, variant, bytes, cursor)
        case bytes.getbyte(cursor)
        when 0x2A # *
          directive.length_type, directive.length = star(directive.type, variant)
          cursor + 1
        when 0x30..0x39
          directive.length_type = :LENGTH_FIXED
          digits = bytes.byteslice(cursor..)[/\A\d+/]
          # strtoumaxc: an overflow is found before a multiplication, and
          # the value wraps as a uintmax_t does.
          overflow = false
          directive.length = digits.each_byte.reduce(0) do |value, digit|
            overflow ||= value > UINT64_MAX / 10
            (value * 10 + digit - 0x30) & UINT64_MAX
          end
          raise RangeError, "pack length too big".b if overflow

          cursor + digits.bytesize
        else
          cursor
        end
      end

      # The length type and length a `*` gives each type.
      def star(type, variant)
        unpack = variant == :unpack
        case type
        when :NULL, :BACK then [unpack ? :LENGTH_MAX : :LENGTH_FIXED, 0]
        when :MOVE then [unpack ? :LENGTH_RELATIVE : :LENGTH_FIXED, 0]
        when :STRING_UU then [:LENGTH_FIXED, 0]
        when :STRING_FIXED then unpack ? [:LENGTH_MAX, 0] : [:LENGTH_FIXED, 1]
        when :STRING_MIME, :STRING_BASE64 then [:LENGTH_FIXED, 1]
        else [:LENGTH_MAX, 0]
        end
      end
    end
  end
end
