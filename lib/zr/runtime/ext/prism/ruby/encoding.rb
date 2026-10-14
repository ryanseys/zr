# frozen_string_literal: true
# shareable_constant_value: literal

require_relative "encoding_tables"

module Prism
  module Ruby
    # encoding.c: the functions that the lexer calls on the encoding of a
    # source, for the 90 encodings that prism knows. Each takes the binary
    # source, a byte offset and the bytes left from there (C's `n`, which
    # can be 0 or less). It returns a width in bytes, 0 for no character,
    # or true or false for isupper_char.
    module Encodings
      ALPHABETIC = 1
      ALPHANUMERIC = 2
      UPPERCASE = 4

      # pm_unicode_codepoint_match: a binary search over inclusive ranges.
      def self.codepoint_in?(codepoint, ranges)
        low = 0
        high = ranges.size
        while low < high
          middle = low + (high - low) / 2
          middle -= 1 if middle.odd?
          return true if codepoint >= ranges[middle] && codepoint <= ranges[middle + 1]

          if codepoint < ranges[middle]
            high = middle
          else
            low = middle + 2
          end
        end
        false
      end

      # A pm_encoding_t: its name, whether it is multibyte, and the four
      # functions. The base implements them with the ASCII table, as the
      # ascii_*_char functions do.
      class Encoding
        attr_reader :name

        def initialize(name, multibyte)
          @name = name.freeze
          @multibyte = multibyte
        end

        def multibyte? = @multibyte

        # pm_encoding_single_char_width
        def char_width(_source, _at, _n) = 1

        # pm_encoding_ascii_alpha_char, which returns the table bit itself.
        def alpha_char(source, at, n) = n > 0 ? ASCII_TABLE.getbyte(source.getbyte(at)) & ALPHABETIC : 0

        # pm_encoding_ascii_alnum_char
        def alnum_char(source, at, n) = n > 0 && ASCII_TABLE.getbyte(source.getbyte(at)).anybits?(ALPHANUMERIC) ? 1 : 0

        # pm_encoding_ascii_isupper_char
        def isupper_char(source, at, n) = n > 0 && ASCII_TABLE.getbyte(source.getbyte(at)).anybits?(UPPERCASE)

        def inspect = "#<#{self.class.name} #{@name}>"
      end

      # US-ASCII: pm_encoding_ascii_char_width, one byte below 0x80.
      class ASCII < Encoding
        def char_width(source, at, n) = n > 0 && source.getbyte(at) < 0x80 ? 1 : 0
      end

      # A single-byte encoding with a byte table of its own
      # (PRISM_ENCODING_TABLE).
      class Table < Encoding
        def initialize(name, table)
          super(name, false)
          @table = table
        end

        def alpha_char(source, at, n) = n > 0 && @table.getbyte(source.getbyte(at)).anybits?(ALPHABETIC) ? 1 : 0
        def alnum_char(source, at, n) = n > 0 && @table.getbyte(source.getbyte(at)).anybits?(ALPHANUMERIC) ? 1 : 0
        def isupper_char(source, at, n) = n > 0 && @table.getbyte(source.getbyte(at)).anybits?(UPPERCASE)
      end

      # Unicode functions over a decoder: the byte table below 0x100, the
      # code point ranges above. C leaves the width of a decoded character
      # unset (pm_utf_8_codepoint never writes it). The compiled C returns
      # the character's own width, and so does this.
      class Unicode < Encoding
        def alpha_char(source, at, n) = unicode_char(source, at, n, ALPHABETIC, UNICODE_ALPHA)
        def alnum_char(source, at, n) = unicode_char(source, at, n, ALPHANUMERIC, UNICODE_ALNUM)
        def isupper_char(source, at, n) = unicode_char(source, at, n, UPPERCASE, UNICODE_ISUPPER).positive?

        private

        def unicode_char(source, at, n, bit, ranges)
          return 0 if n == 0

          byte = source.getbyte(at)
          return UNICODE_TABLE.getbyte(byte).anybits?(bit) ? 1 : 0 if byte < 0x80

          codepoint = codepoint(source, at, n)
          width = char_width(source, at, n)
          if codepoint <= 0xFF
            UNICODE_TABLE.getbyte(codepoint).anybits?(bit) ? width : 0
          else
            Encodings.codepoint_in?(codepoint, ranges) ? width : 0
          end
        end
      end

      # UTF-8 and its variants, over the pm_utf_8_dfa state machine.
      class UTF8 < Unicode
        # pm_encoding_utf_8_char_width
        def char_width(source, at, n)
          state = 0
          [n, 4].min.times do |index|
            state = UTF_8_DFA[256 + state * 16 + UTF_8_DFA[source.getbyte(at + index)]]
            return index + 1 if state == 0
          end
          0
        end

        # pm_utf_8_codepoint
        def codepoint(source, at, n)
          state = 0
          codepoint = 0
          [n, 4].min.times do |index|
            byte = source.getbyte(at + index)
            type = UTF_8_DFA[byte]
            codepoint = state != 0 ? (byte & 0x3F) | (codepoint << 6) : (0xFF >> type) & byte
            state = UTF_8_DFA[256 + state * 16 + type]
            return codepoint if state == 0
          end
          0
        end
      end

      # CESU-8: surrogate pairs as two three-byte sequences.
      class CESU8 < Unicode
        # pm_encoding_cesu_8_char_width
        def char_width(source, at, n)
          return 0 if n == 0

          b = ->(i) { source.getbyte(at + i) }
          if b.(0) < 0x80
            1
          elsif n > 1 && b.(0) >= 0xC2 && b.(0) <= 0xDF && b.(1) >= 0x80 && b.(1) <= 0xBF
            2
          elsif n > 5 && b.(0) == 0xED && b.(1) >= 0xA0 && b.(1) <= 0xAF && b.(2) >= 0x80 && b.(2) <= 0xBF &&
                b.(3) == 0xED && b.(4) >= 0xB0 && b.(4) <= 0xBF && b.(5) >= 0x80 && b.(5) <= 0xBF
            6
          elsif n > 2 && b.(0) == 0xED && b.(1) >= 0xA0 && b.(1) <= 0xBF
            3
          elsif n > 2 && ((b.(0) == 0xE0 && b.(1) >= 0xA0) || (b.(0) >= 0xE1 && b.(0) <= 0xEF && b.(1) >= 0x80)) && b.(1) <= 0xBF && b.(2) >= 0x80 && b.(2) <= 0xBF
            3
          else
            0
          end
        end

        # pm_cesu_8_codepoint
        def codepoint(source, at, n)
          b = ->(i) { source.getbyte(at + i) }
          if n > 0 && b.(0) < 0x80
            b.(0)
          elsif n > 1 && b.(0) >= 0xC2 && b.(0) <= 0xDF && b.(1) >= 0x80 && b.(1) <= 0xBF
            ((b.(0) & 0x1F) << 6) | (b.(1) & 0x3F)
          elsif n > 5 && b.(0) == 0xED && b.(1) >= 0xA0 && b.(1) <= 0xAF && b.(2) >= 0x80 && b.(2) <= 0xBF &&
                b.(3) == 0xED && b.(4) >= 0xB0 && b.(4) <= 0xBF && b.(5) >= 0x80 && b.(5) <= 0xBF
            0x10000 + (((b.(1) & 0xF) << 16) | ((b.(2) & 0x3F) << 10) | ((b.(4) & 0xF) << 6) | (b.(5) & 0x3F))
          elsif n > 2 && b.(0) == 0xED && b.(1) >= 0xA0 && b.(1) <= 0xBF
            0x10000 + (((b.(0) & 0x03) << 16) | ((b.(1) & 0x3F) << 10) | (b.(2) & 0x3F))
          elsif n > 2 && ((b.(0) == 0xE0 && b.(1) >= 0xA0) || (b.(0) >= 0xE1 && b.(0) <= 0xEF && b.(1) >= 0x80)) && b.(1) <= 0xBF && b.(2) >= 0x80 && b.(2) <= 0xBF
            ((b.(0) & 0xF) << 12) | ((b.(1) & 0x3F) << 6) | (b.(2) & 0x3F)
          else
            0
          end
        end
      end

      # A multibyte encoding whose letters are ASCII's alone
      # (pm_encoding_ascii_*_char_7bit), and whose width is one of
      # encoding.c's width functions.
      class Multibyte < Encoding
        def initialize(name, width, isupper)
          super(name, true)
          @width = width
          @isupper = isupper
        end

        def char_width(source, at, n) = send(@width, source, at, n)

        def alpha_char(source, at, n) = n > 0 && source.getbyte(at) < 0x80 ? super : 0
        def alnum_char(source, at, n) = n > 0 && source.getbyte(at) < 0x80 ? super : 0

        def isupper_char(source, at, n)
          case @isupper
          when :euc_jp
            # pm_encoding_euc_jp_isupper_char
            case euc_jp(source, at, n)
            when 1 then super(source, at, n)
            when 2
              b0 = source.getbyte(at)
              b1 = source.getbyte(at + 1)
              (b0 == 0xA3 && b1 >= 0xC1 && b1 <= 0xDA) || (b0 == 0xA6 && b1 >= 0xA1 && b1 <= 0xB8) || (b0 == 0xA7 && b1 >= 0xA1 && b1 <= 0xC1)
            else false
            end
          else
            # pm_encoding_ascii_isupper_char_7bit
            n > 0 && source.getbyte(at) < 0x80 && super
          end
        end

        private

        # pm_encoding_euc_jp_char_width
        def euc_jp(source, at, n)
          b0 = n > 0 ? source.getbyte(at) : nil
          return 1 if n > 0 && b0 < 0x80
          return 2 if n > 1 && (b0 == 0x8E || (b0 >= 0xA1 && b0 <= 0xFE)) && source.getbyte(at + 1).between?(0xA1, 0xFE)
          # C tests b[2] <= 0xFE where it means b[1]; the port keeps the test.
          return 3 if n > 2 && b0 == 0x8F && source.getbyte(at + 1) >= 0xA1 && source.getbyte(at + 2) <= 0xFE && source.getbyte(at + 2) >= 0xA1

          0
        end

        # pm_encoding_big5_char_width
        def big5(source, at, n)
          return 1 if n > 0 && source.getbyte(at) < 0x80
          return 0 unless n > 1

          b0 = source.getbyte(at)
          b1 = source.getbyte(at + 1)
          b0.between?(0xA1, 0xFE) && (b1.between?(0x40, 0x7E) || b1.between?(0xA1, 0xFE)) ? 2 : 0
        end

        # pm_encoding_cp949_char_width
        def cp949(source, at, n)
          return 1 if n > 0 && source.getbyte(at) <= 0x80
          return 0 unless n > 1

          b0 = source.getbyte(at)
          b1 = source.getbyte(at + 1)
          b0.between?(0x81, 0xFE) && (b1.between?(0x41, 0x5A) || b1.between?(0x61, 0x7A) || b1.between?(0x81, 0xFE)) ? 2 : 0
        end

        # pm_encoding_emacs_mule_char_width
        def emacs_mule(source, at, n)
          b = ->(i) { source.getbyte(at + i) }
          return 1 if n > 0 && b.(0) < 0x80
          return 2 if n > 1 && b.(0).between?(0x81, 0x8F) && b.(1) >= 0xA0
          if n > 2 && ((b.(0).between?(0x90, 0x99) && b.(1) >= 0xA0) || ((b.(0) == 0x9A || b.(0) == 0x9B) && b.(1).between?(0xE0, 0xEF))) && b.(2) >= 0xA0
            return 3
          end
          if n > 3 && ((b.(0) == 0x9C && b.(1).between?(0xF0, 0xF4)) || (b.(0) == 0x9D && b.(1).between?(0xF5, 0xFE))) && b.(2) >= 0xA0 && b.(3) >= 0xA0
            return 4
          end

          0
        end

        # pm_encoding_euc_kr_char_width
        def euc_kr(source, at, n)
          return 1 if n > 0 && source.getbyte(at) < 0x80

          n > 1 && source.getbyte(at).between?(0xA1, 0xFE) && source.getbyte(at + 1).between?(0xA1, 0xFE) ? 2 : 0
        end

        # pm_encoding_euc_tw_char_width
        def euc_tw(source, at, n)
          b = ->(i) { source.getbyte(at + i) }
          return 1 if n > 0 && b.(0) < 0x80
          return 2 if n > 1 && b.(0).between?(0xA1, 0xFE) && b.(1).between?(0xA1, 0xFE)
          return 4 if n > 3 && b.(0) == 0x8E && b.(1).between?(0xA1, 0xB0) && b.(2).between?(0xA1, 0xFE) && b.(3).between?(0xA1, 0xFE)

          0
        end

        # pm_encoding_gb18030_char_width
        def gb18030(source, at, n)
          b = ->(i) { source.getbyte(at + i) }
          return 1 if n > 0 && b.(0) < 0x80
          return 2 if n > 1 && b.(0).between?(0x81, 0xFE) && b.(1).between?(0x40, 0xFE) && b.(1) != 0x7F
          return 4 if n > 3 && b.(0).between?(0x81, 0xFE) && b.(1).between?(0x30, 0x39) && b.(2).between?(0x81, 0xFE) && b.(3).between?(0x30, 0x39)

          0
        end

        # pm_encoding_gbk_char_width
        def gbk(source, at, n)
          return 1 if n > 0 && source.getbyte(at) <= 0x80
          return 0 unless n > 1

          b0 = source.getbyte(at)
          b1 = source.getbyte(at + 1)
          double =
            (b0.between?(0xA1, 0xA9) && b1.between?(0xA1, 0xFE)) || # GBK/1
            (b0.between?(0xB0, 0xF7) && b1.between?(0xA1, 0xFE)) || # GBK/2
            (b0.between?(0x81, 0xA0) && b1.between?(0x40, 0xFE) && b1 != 0x7F) || # GBK/3
            (b0.between?(0xAA, 0xFE) && b1.between?(0x40, 0xA0) && b1 != 0x7F) || # GBK/4
            (b0.between?(0xA8, 0xA9) && b1.between?(0x40, 0xA0) && b1 != 0x7F) || # GBK/5
            (b0.between?(0xAA, 0xAF) && b1.between?(0xA1, 0xFE)) || # user-defined 1
            (b0.between?(0xF8, 0xFE) && b1.between?(0xA1, 0xFE)) || # user-defined 2
            (b0.between?(0xA1, 0xA7) && b1.between?(0x40, 0xA0) && b1 != 0x7F) # user-defined 3
          double ? 2 : 0
        end
      end

      # Shift_JIS and its kin, whose single bytes above 0x80 count as letters.
      class ShiftJIS < Encoding
        def initialize(name) = super(name, true)

        # pm_encoding_shift_jis_char_width
        def char_width(source, at, n)
          return 0 if n == 0

          b0 = source.getbyte(at)
          return 1 if b0 < 0x80 || b0.between?(0xA1, 0xDF)
          return 2 if n > 1 && (b0.between?(0x81, 0x9F) || b0.between?(0xE0, 0xFC)) && (b1 = source.getbyte(at + 1)).between?(0x40, 0xFC) && b1 != 0x7F

          0
        end

        # pm_encoding_shift_jis_alnum_char and _alpha_char
        def alnum_char(source, at, n) = letter(source, at, n) { super(source, at, n) }
        def alpha_char(source, at, n) = letter(source, at, n) { super(source, at, n) }

        # pm_encoding_shift_jis_isupper_char, which returns the width (0)
        # for a byte that is not a character.
        def isupper_char(source, at, n)
          case (width = char_width(source, at, n))
          when 1 then super
          when 2
            b0 = source.getbyte(at)
            b1 = source.getbyte(at + 1)
            (b0 == 0x82 && b1.between?(0x60, 0x79)) || (b0 == 0x83 && b1.between?(0x9F, 0xB6)) || (b0 == 0x84 && b1.between?(0x40, 0x60))
          else
            width != 0
          end
        end

        private

        def letter(source, at, n)
          width = char_width(source, at, n)
          return width unless width == 1

          source.getbyte(at) >= 0x80 || yield.positive? ? 1 : 0
        end
      end

      # pm_encodings, by pm_encoding_type_t name.
      ALL = ENCODINGS.to_h do |id, (name, width, alnum, _alpha, isupper, multibyte)|
        encoding =
          case width
          when "utf_8_char_width" then UTF8.new(name, multibyte)
          when "cesu_8_char_width" then CESU8.new(name, multibyte)
          when "shift_jis_char_width" then ShiftJIS.new(name)
          when "ascii_char_width" then ASCII.new(name, multibyte)
          when "single_char_width"
            table = alnum.delete_suffix("_alnum_char")
            # A table that holds ASCII's bytes has no index.
            index = TABLES[table]
            index ? Table.new(name, TABLE_BYTES.byteslice(index * 256, 256).freeze) : Encoding.new(name, multibyte)
          else
            Multibyte.new(name, width.delete_suffix("_char_width").to_sym, isupper == "euc_jp_isupper_char" ? :euc_jp : :ascii)
          end
        [id, encoding.freeze]
      end.freeze

      UTF_8 = ALL.fetch(:UTF_8)
      US_ASCII = ALL.fetch(:US_ASCII)
      ASCII_8BIT = ALL.fetch(:ASCII_8BIT)

      LOOKUP = NAMES.to_h { |name, id| [name.downcase(:ascii), ALL.fetch(id)] }.freeze
      private_constant :LOOKUP

      # pm_encoding_find: the encoding that a magic comment or an option
      # gives, or nil. Case does not matter, and UTF-8 can have a suffix.
      def self.find(bytes)
        bytes = bytes.b.downcase(:ascii)
        if bytes.start_with?("utf-8")
          return ALL.fetch(:UTF8_MAC) if bytes == "utf-8-hfs"

          return UTF_8
        end
        bytes.bytesize >= 3 ? LOOKUP[bytes] : nil
      end
    end
  end
end
