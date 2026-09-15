# frozen_string_literal: true

# The character tests of libyaml 0.2.5 (src/yaml_private.h). Each one
# looks at the UTF-8 bytes of `string` at byte offset `at`, the way the
# C macros look at `string.pointer[offset]`.
#
# libyaml's strings end with a NUL byte, so a test past the last byte
# sees 0. `getbyte` answers nil there, and the tests read nil as 0.
module Psych
  module LibYAML
    module Chars
      private

      # CHECK_AT
      def check_at?(string, octet, at) = string.getbyte(at) == octet

      # IS_ALPHA_AT: a digit, a letter, '_' or '-'.
      def alpha_at?(string, at)
        octet = string.getbyte(at) || 0
        (octet >= 0x30 && octet <= 0x39) || (octet >= 0x41 && octet <= 0x5A) ||
          (octet >= 0x61 && octet <= 0x7A) || octet == 0x5F || octet == 0x2D
      end

      # IS_DIGIT_AT
      def digit_at?(string, at)
        octet = string.getbyte(at) || 0
        octet >= 0x30 && octet <= 0x39
      end

      # AS_DIGIT_AT
      def as_digit_at(string, at) = string.getbyte(at) - 0x30

      # IS_HEX_AT
      def hex_at?(string, at)
        octet = string.getbyte(at) || 0
        (octet >= 0x30 && octet <= 0x39) || (octet >= 0x41 && octet <= 0x46) ||
          (octet >= 0x61 && octet <= 0x66)
      end

      # AS_HEX_AT
      def as_hex_at(string, at)
        octet = string.getbyte(at)
        if octet >= 0x41 && octet <= 0x46
          octet - 0x41 + 10
        elsif octet >= 0x61 && octet <= 0x66
          octet - 0x61 + 10
        else
          octet - 0x30
        end
      end

      # IS_ASCII_AT
      def ascii_at?(string, at) = (string.getbyte(at) || 0) <= 0x7F

      # IS_PRINTABLE_AT: a character YAML can show without an escape.
      def printable_at?(string, at)
        octet = string.getbyte(at) || 0
        return true if octet == 0x0A
        return true if octet >= 0x20 && octet <= 0x7E
        return (string.getbyte(at + 1) || 0) >= 0xA0 if octet == 0xC2
        return true if octet > 0xC2 && octet < 0xED
        return (string.getbyte(at + 1) || 0) < 0xA0 if octet == 0xED
        return true if octet == 0xEE

        if octet == 0xEF
          second = string.getbyte(at + 1) || 0
          third = string.getbyte(at + 2) || 0
          return !(second == 0xBB && third == 0xBF) && !(second == 0xBF && (third == 0xBE || third == 0xBF))
        end
        false
      end

      # IS_Z_AT
      def z_at?(string, at) = (string.getbyte(at) || 0).zero?

      # IS_BOM_AT
      def bom_at?(string, at)
        string.getbyte(at) == 0xEF && string.getbyte(at + 1) == 0xBB && string.getbyte(at + 2) == 0xBF
      end

      # IS_SPACE_AT
      def space_at?(string, at) = string.getbyte(at) == 0x20

      # IS_TAB_AT
      def tab_at?(string, at) = string.getbyte(at) == 0x09

      # IS_BLANK_AT: a space or a tab.
      def blank_at?(string, at)
        octet = string.getbyte(at)
        octet == 0x20 || octet == 0x09
      end

      # IS_BREAK_AT: CR, LF, NEL, LS or PS.
      def break_at?(string, at)
        case string.getbyte(at)
        when 0x0D, 0x0A then true
        when 0xC2 then string.getbyte(at + 1) == 0x85
        when 0xE2
          string.getbyte(at + 1) == 0x80 && ((third = string.getbyte(at + 2)) == 0xA8 || third == 0xA9)
        else false
        end
      end

      # IS_CRLF_AT
      def crlf_at?(string, at) = string.getbyte(at) == 0x0D && string.getbyte(at + 1) == 0x0A

      # IS_BREAKZ_AT: a line break or NUL.
      def breakz_at?(string, at) = break_at?(string, at) || z_at?(string, at)

      # IS_BLANKZ_AT: a space, a tab, a line break or NUL.
      def blankz_at?(string, at) = blank_at?(string, at) || breakz_at?(string, at)

      # WIDTH_AT: the byte length of the UTF-8 character that starts here.
      def width_at(string, at)
        octet = string.getbyte(at) || 0
        if octet & 0x80 == 0x00 then 1
        elsif octet & 0xE0 == 0xC0 then 2
        elsif octet & 0xF0 == 0xE0 then 3
        elsif octet & 0xF8 == 0xF0 then 4
        else 0
        end
      end

      # A NUL-terminated view of a string: the bytes before the first NUL,
      # which is what strlen, strcmp and strdup see.
      def c_string(string)
        cut = string.index("\0")
        cut ? string.byteslice(0, cut) : string
      end

      # A new, empty, binary string buffer.
      def new_string = String.new(encoding: Encoding::BINARY)
    end
  end
end
