# frozen_string_literal: true
# shareable_constant_value: literal

module Prism
  module Ruby
    # util/pm_char.c: which bytes are whitespace, digits and regexp option
    # letters, and how far a run of them goes. A run starts at `from` in the
    # binary source and stops before `limit` (C's `string + length`).
    module Characters
      WHITESPACE = 1
      INLINE_WHITESPACE = 2
      REGEXP_OPTION = 4

      BINARY_DIGIT = 1
      BINARY_NUMBER = 2
      OCTAL_DIGIT = 4
      OCTAL_NUMBER = 8
      DECIMAL_DIGIT = 16
      DECIMAL_NUMBER = 32
      HEXADECIMAL_DIGIT = 64
      HEXADECIMAL_NUMBER = 128

      # pm_byte_table
      BYTE_TABLE = Array.new(256, 0).tap do |table|
        [0x09, 0x0B, 0x0C, 0x0D, 0x20].each { |b| table[b] = WHITESPACE | INLINE_WHITESPACE }
        table[0x0A] = WHITESPACE
        [*"A".."Z", *"a".."z"].each { |c| table[c.ord] = REGEXP_OPTION }
      end.freeze

      # pm_number_table
      NUMBER_TABLE = Array.new(256, 0).tap do |table|
        "01".each_byte { |b| table[b] = 0xff }
        "234567".each_byte { |b| table[b] = 0xfc }
        "89".each_byte { |b| table[b] = 0xf0 }
        "abcdefABCDEF".each_byte { |b| table[b] = 0xc0 }
        table["_".ord] = 0xaa
      end.freeze

      private

      def whitespace?(byte) = BYTE_TABLE[byte].anybits?(WHITESPACE)
      def inline_whitespace?(byte) = BYTE_TABLE[byte].anybits?(INLINE_WHITESPACE)
      def binary_digit?(byte) = NUMBER_TABLE[byte].anybits?(BINARY_DIGIT)
      def octal_digit?(byte) = NUMBER_TABLE[byte].anybits?(OCTAL_DIGIT)
      def decimal_digit?(byte) = NUMBER_TABLE[byte].anybits?(DECIMAL_DIGIT)
      def hexadecimal_digit?(byte) = NUMBER_TABLE[byte].anybits?(HEXADECIMAL_DIGIT)

      # pm_strspn_char_kind
      def strspn_char_kind(from, limit, kind)
        cursor = from
        cursor += 1 while cursor < limit && BYTE_TABLE[@source.getbyte(cursor)].anybits?(kind)
        cursor - from
      end

      def strspn_inline_whitespace(from, limit) = strspn_char_kind(from, limit, INLINE_WHITESPACE)
      def strspn_regexp_option(from, limit) = strspn_char_kind(from, limit, REGEXP_OPTION)

      # pm_strspn_whitespace_newlines: the run, with each newline in it added
      # to the newline list.
      def strspn_whitespace_newlines(from, limit)
        cursor = from
        while cursor < limit && BYTE_TABLE[byte = @source.getbyte(cursor)].anybits?(WHITESPACE)
          newline_append(cursor) if byte == 0x0A
          cursor += 1
        end
        cursor - from
      end

      # pm_strspn_number_kind
      def strspn_number_kind(from, limit, kind)
        cursor = from
        cursor += 1 while cursor < limit && NUMBER_TABLE[@source.getbyte(cursor)].anybits?(kind)
        cursor - from
      end

      # pm_strspn_number_kind_underscores: the run, and the offset of an
      # underscore that follows another or ends the run (the last one found),
      # or nil.
      def strspn_number_kind_underscores(from, limit, kind)
        cursor = from
        invalid = nil
        underscore = false
        while cursor < limit && NUMBER_TABLE[byte = @source.getbyte(cursor)].anybits?(kind)
          if byte == 0x5F
            invalid = cursor if underscore
            underscore = true
          else
            underscore = false
          end
          cursor += 1
        end
        invalid = cursor - 1 if cursor > from && @source.getbyte(cursor - 1) == 0x5F
        [cursor - from, invalid]
      end

      def strspn_decimal_digit(from, limit) = strspn_number_kind(from, limit, DECIMAL_DIGIT)
      def strspn_hexadecimal_digit(from, limit) = strspn_number_kind(from, limit, HEXADECIMAL_DIGIT)
      def strspn_binary_number(from, limit) = strspn_number_kind_underscores(from, limit, BINARY_NUMBER)
      def strspn_octal_number(from, limit) = strspn_number_kind_underscores(from, limit, OCTAL_NUMBER)
      def strspn_decimal_number(from, limit) = strspn_number_kind_underscores(from, limit, DECIMAL_NUMBER)
      def strspn_hexadecimal_number(from, limit) = strspn_number_kind_underscores(from, limit, HEXADECIMAL_NUMBER)
    end
  end
end
