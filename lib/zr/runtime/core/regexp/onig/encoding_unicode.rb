# frozen_string_literal: true

# Derived from Onigmo (BSD-2-Clause); see THIRD_PARTY_NOTICES.md.
#
# Onigmo's Unicode encodings: UTF-8 (enc/utf_8.c), CESU-8 (cesu_8.c),
# UTF-16LE/BE (utf_16le.c, utf_16be.c) and UTF-32LE/BE (utf_32le.c,
# utf_32be.c), over the tables and folds of enc/unicode.c with Unicode
# 17.0's data. A port under the BSD-2-Clause license reproduced in
# regexp.rb.
class Regexp
  module Onig
    module Enc
      # enc/unicode.c: what every Unicode encoding reads the same way,
      # over its own mbc_to_code, code_to_mbc and enclen.
      module UnicodeEncoding
        PROPERTY_NAME_MAX_SIZE = 46

        def unicode? = true

        # onigenc_unicode_is_code_ctype
        def code_ctype?(code, ctype)
          return Unicode.ctype_bit?(code, ctype) if ctype <= CType::MAX_STD && code < 256
          raise Error.new(Err::TYPE_BUG) if ctype >= Unicode.table_count

          Unicode.in_code_range?(Unicode.ranges(ctype), code)
        end

        # get_ctype_code_range (utf_8.c, cesu_8.c) and
        # onigenc_utf16_32_get_ctype_code_range: [sb_out, ranges]
        def ctype_code_range(ctype)
          raise Error.new(Err::TYPE_BUG) if ctype >= Unicode.table_count

          [sb_out, Unicode.ranges(ctype)]
        end

        # onigenc_unicode_property_name_to_ctype: the name with spaces,
        # hyphens and underscores dropped and lowercased, looked up.
        def property_name_to_ctype(s, p, e, reader = self)
          buf = +""
          while p < e
            code = reader.mbc_to_code(s, p, e)
            p += reader.enclen(s, p, e)
            next if code == 0x20 || code == 0x2d || code == 0x5f
            return Err::INVALID_CHAR_PROPERTY_NAME if code >= 0x80

            buf << ascii_lower(code).chr
            return Err::INVALID_CHAR_PROPERTY_NAME if buf.size >= PROPERTY_NAME_MAX_SIZE
          end
          Unicode.properties.fetch(buf, Err::INVALID_CHAR_PROPERTY_NAME)
        end

        # onigenc_unicode_mbc_case_fold: [the folded bytes, the bytes read]
        def unicode_mbc_case_fold(s, p, e)
          code = mbc_to_code(s, p, e)
          len = enclen(s, p, e)
          to = Unicode.fold(code)
          return [s.byteslice(p, len), len] if to.nil?

          [to.map { |c| code_to_mbc(c) }.join, len]
        end

        # onigenc_unicode_apply_all_case_fold, without the Turkic branch.
        def apply_all_case_fold(flag)
          Unicode.folds(1).each do |from, to|
            to.each_with_index do |code, j|
              yield code, [from]
              yield from, [code]
              j.times do |k|
                yield code, [to[k]]
                yield to[k], [code]
              end
            end
          end
          return if (flag & CASE_FOLD_MULTI_CHAR) == 0

          [Unicode.folds(2), Unicode.folds(3)].each do |table|
            table.each do |from, to|
              to.each_with_index do |code, j|
                yield code, from
                to.each_with_index do |other, k|
                  next if k == j

                  yield code, [other]
                end
              end
            end
          end
        end

        # onigenc_unicode_get_case_fold_codes_by_str: every string the
        # character(s) at `p` match under case folding, as
        # [byte length, codes] items.
        def case_fold_codes_by_str(flag, s, p, e)
          items = []
          code = mbc_to_code(s, p, e)
          len = enclen(s, p, e)

          to = Unicode.fold(code)
          if to
            if to.size == 1
              orig_code = code
              items << [len, [to[0]]]
              code = to[0]
              unfold = Unicode.unfold1(code)
              unfold&.each { |c| items << [len, [c]] if c != orig_code }
            elsif (flag & CASE_FOLD_MULTI_CHAR) != 0
              cs = to.map { |c| [c] + (Unicode.unfold1(c) || []) }
              if to.size == 2
                cs[0].each { |a| cs[1].each { |b| items << [len, [a, b]] } }
                z2 = Unicode.unfold2(to)
                z2&.each { |c| items << [len, [c]] if c != code }
              else
                cs[0].each { |a| cs[1].each { |b| cs[2].each { |c| items << [len, [a, b, c]] } } }
                z3 = Unicode.unfold3(to)
                z3&.each { |c| items << [len, [c]] if c != code }
              end
              # multi char folded code is not head of another folded multi char
              flag = 0
            end
          else
            unfold = Unicode.unfold1(code)
            unfold&.each { |c| items << [len, [c]] }
          end

          if (flag & CASE_FOLD_MULTI_CHAR) != 0
            p += len
            if p < e
              codes = [code]
              code = mbc_to_code(s, p, e)
              to = Unicode.fold(code)
              codes << (to && to.size == 1 ? to[0] : code)
              clen = enclen(s, p, e)
              len += clen
              z2 = Unicode.unfold2(codes)
              z2&.each { |c| items << [len, [c]] }

              p += clen
              if p < e
                code = mbc_to_code(s, p, e)
                to = Unicode.fold(code)
                codes << (to && to.size == 1 ? to[0] : code)
                clen = enclen(s, p, e)
                len += clen
                z3 = Unicode.unfold3(codes)
                z3&.each { |c| items << [len, [c]] }
              end
            end
          end
          items
        end
      end

      # OnigEncodingUTF_8 with Unicode 17.0's tables.
      class UTF8 < Base
        include UnicodeEncoding

        INVALID_CODE_FE = 0xfffffffe
        INVALID_CODE_FF = 0xffffffff
        VALID_CODE_LIMIT = 0x10ffff

        def name = "UTF-8"
        def max_len = 4
        def min_len = 1
        def sb_out = 0x80

        ACCEPT = -1
        FAILURE = -2

        # utf_8.c's `trans` automaton: the state a lead byte starts, and
        # the state each continuation byte moves to.
        LEAD = Array.new(256) do |b|
          if b < 0x80 then ACCEPT
          elsif b < 0xc2 then FAILURE
          elsif b < 0xe0 then 1
          elsif b == 0xe0 then 2
          elsif b < 0xed then 3
          elsif b == 0xed then 4
          elsif b < 0xf0 then 3
          elsif b == 0xf0 then 5
          elsif b < 0xf4 then 6
          elsif b == 0xf4 then 7
          else FAILURE
          end
        end.freeze

        # [low, high, next state] for each state 1..7.
        TRANS = [
          nil,
          [0x80, 0xbf, ACCEPT],
          [0xa0, 0xbf, 1],
          [0x80, 0xbf, 1],
          [0x80, 0x9f, 1],
          [0x90, 0xbf, 3],
          [0x80, 0xbf, 3],
          [0x80, 0x8f, 3],
        ].freeze

        LENGTHS = Array.new(256) do |b|
          if b < 0xc2 then 1
          elsif b < 0xe0 then 2
          elsif b < 0xf0 then 3
          elsif b < 0xf5 then 4
          else 1
          end
        end.freeze

        # mbc_enc_len: the character's length, -1 for an invalid
        # sequence, -1-n when n more bytes past `e` would be needed.
        def precise_len(s, p, e)
          first = s.getbyte(p)
          state = LEAD[first]
          return state == ACCEPT ? 1 : -1 if state < 0

          n = 1
          loop do
            return -1 - (LENGTHS[first] - n) if p + n == e

            lo, hi, nxt = TRANS[state]
            byte = s.getbyte(p + n)
            state = byte >= lo && byte <= hi ? nxt : FAILURE
            n += 1
            return state == ACCEPT ? n : -1 if state < 0
          end
        end

        def mbc_to_code(s, p, e)
          len = precise_len(s, p, e)
          c = s.getbyte(p)
          if len > 1
            len -= 1
            n = c & ((1 << (6 - len)) - 1)
            i = 1
            while len > 0
              n = (n << 6) | (s.getbyte(p + i) & 0x3f)
              i += 1
              len -= 1
            end
            n
          elsif c > 0xfd
            c == 0xfe ? INVALID_CODE_FE : INVALID_CODE_FF
          else
            c
          end
        end

        def code_to_mbclen(code)
          if (code & 0xffffff80) == 0 then 1
          elsif (code & 0xfffff800) == 0 then 2
          elsif (code & 0xffff0000) == 0 then 3
          elsif code <= VALID_CODE_LIMIT then 4
          elsif code == INVALID_CODE_FE || code == INVALID_CODE_FF then 1
          else Err::TOO_BIG_WIDE_CHAR_VALUE
          end
        end

        def code_to_mbc(code)
          if (code & 0xffffff80) == 0
            code.chr.b
          elsif (code & 0xfffff800) == 0
            [((code >> 6) & 0x1f) | 0xc0, (code & 0x3f) | 0x80].pack("C*")
          elsif (code & 0xffff0000) == 0
            [((code >> 12) & 0x0f) | 0xe0, ((code >> 6) & 0x3f) | 0x80, (code & 0x3f) | 0x80].pack("C*")
          elsif code <= VALID_CODE_LIMIT
            [((code >> 18) & 0x07) | 0xf0, ((code >> 12) & 0x3f) | 0x80, ((code >> 6) & 0x3f) | 0x80, (code & 0x3f) | 0x80].pack("C*")
          elsif code == INVALID_CODE_FE
            "\xfe".b
          elsif code == INVALID_CODE_FF
            "\xff".b
          else
            raise Error.new(Err::TOO_BIG_WIDE_CHAR_VALUE)
          end
        end

        def left_adjust_char_head(s, start, p, _e)
          return p if p <= start

          p -= 1 while (s.getbyte(p) & 0xc0) == 0x80 && p > start
          p
        end

        # utf_8.c mbc_case_fold
        def mbc_case_fold(_flag, s, p, e)
          byte = s.getbyte(p)
          return [ascii_lower(byte).chr.b, 1] if byte < 128

          unicode_mbc_case_fold(s, p, e)
        end

        def kernel_kind = KIND_UTF8
      end

      UTF8_ENC = UTF8.new.freeze

      # OnigEncodingCESU_8: UTF-8 whose characters past the BMP are two
      # three-byte surrogates.
      class CESU8 < Base
        include UnicodeEncoding

        INVALID_CODE_FE = 0xfffffffe
        INVALID_CODE_FF = 0xffffffff
        VALID_CODE_LIMIT = 0x10ffff

        def name = "CESU-8"
        def max_len = 6
        def min_len = 1
        def sb_out = 0x80

        def initialize
          @len, @trans, = EncTables::CESU_8
        end

        def precise_len(s, p, e)
          first = s.getbyte(p)
          state = Enc.trans(@trans, 0, first)
          k = 1
          loop do
            return state == -1 ? k : INVALID if state < 0
            return INVALID if k == 6

            if p + k == e
              need = case k
                     when 1 then @len.getbyte(first) - 1
                     when 2 then (state == 4 ? 6 : @len.getbyte(first)) - 2
                     else 6 - k
                     end
              return -1 - need
            end
            state = Enc.trans(@trans, state, s.getbyte(p + k))
            k += 1
          end
        end

        def decode3(s, p) = ((s.getbyte(p) & 0xf) << 12) | ((s.getbyte(p + 1) & 0x3f) << 6) | (s.getbyte(p + 2) & 0x3f)

        def mbc_to_code(s, p, e)
          case precise_len(s, p, e)
          when 1 then s.getbyte(p)
          when 2 then ((s.getbyte(p) & 0x1f) << 6) | (s.getbyte(p + 1) & 0x3f)
          when 3 then decode3(s, p)
          when 6 then ((decode3(s, p) & 0x03ff) << 10) + (decode3(s, p + 3) & 0x03ff) + 0x10000
          else
            c = s.getbyte(p)
            if c > 0xfd
              c == 0xfe ? INVALID_CODE_FE : INVALID_CODE_FF
            else
              c
            end
          end
        end

        def code_to_mbclen(code)
          if (code & 0xffffff80) == 0 then 1
          elsif (code & 0xfffff800) == 0 then 2
          elsif (code & 0xffff0000) == 0 then 3
          elsif code <= VALID_CODE_LIMIT then 6
          elsif code == INVALID_CODE_FE || code == INVALID_CODE_FF then 1
          else Err::TOO_BIG_WIDE_CHAR_VALUE
          end
        end

        def code_to_mbc(code)
          return code.chr.b if (code & 0xffffff80) == 0

          if (code & 0xfffff800) == 0
            [((code >> 6) & 0x1f) | 0xc0, (code & 0x3f) | 0x80].pack("C*")
          elsif (code & 0xffff0000) == 0
            [((code >> 12) & 0x0f) | 0xe0, ((code >> 6) & 0x3f) | 0x80, (code & 0x3f) | 0x80].pack("C*")
          elsif code <= VALID_CODE_LIMIT
            high = (code >> 10) + 0xd7c0
            low = (code & 0x3ff) + 0xdc00
            [((high >> 12) & 0x0f) | 0xe0, ((high >> 6) & 0x3f) | 0x80, (high & 0x3f) | 0x80,
             ((low >> 12) & 0x0f) | 0xe0, ((low >> 6) & 0x3f) | 0x80, (low & 0x3f) | 0x80].pack("C*")
          elsif code == INVALID_CODE_FE
            "\xfe".b
          elsif code == INVALID_CODE_FF
            "\xff".b
          else
            raise Error.new(Err::TOO_BIG_WIDE_CHAR_VALUE)
          end
        end

        def left_adjust_char_head(s, start, p, _e)
          return p if p <= start

          q = p
          q -= 1 while (s.getbyte(q) & 0xc0) == 0x80 && q > start
          if q > start && p - q == 2 && (decode3(s, q) >> 10) == 0x37
            pair = q - 1
            pair -= 1 while (s.getbyte(pair) & 0xc0) == 0x80 && pair > start
            return pair if q - pair == 3 && (decode3(s, pair) >> 10) == 0x36
          end
          q
        end

        def mbc_case_fold(_flag, s, p, e)
          byte = s.getbyte(p)
          return [ascii_lower(byte).chr.b, 1] if byte < 128

          unicode_mbc_case_fold(s, p, e)
        end

        def kernel_kind = KIND_CESU8
        def kernel_tables = { len: @len, trans: @trans }
      end

      # UTF16_IS_SURROGATE_FIRST, _SECOND and UTF16_IS_SURROGATE (regenc.h)
      def self.surrogate_first?(c) = (c & 0xfc) == 0xd8
      def self.surrogate_second?(c) = (c & 0xfc) == 0xdc
      def self.surrogate?(c) = (c & 0xf8) == 0xd8

      # UNICODE_VALID_CODEPOINT_P
      def self.valid_codepoint?(c) = c <= 0x10ffff && !(c < 0x10000 && surrogate?(c >> 8))

      # The two UTF-16 encodings.
      class UTF16 < Base
        include UnicodeEncoding

        def max_len = 4
        def min_len = 2
        def sb_out = 0x00
        def code_to_mbclen(code) = code > 0xffff ? 4 : 2
        def allowed_reverse_match?(_s, _p, _e) = false
      end

      class UTF16LE < UTF16
        def name = "UTF-16LE"

        def precise_len(s, p, e)
          len = e - p
          return -1 - 1 if len < 2

          byte = s.getbyte(p + 1)
          return 2 unless Enc.surrogate?(byte)

          if Enc.surrogate_first?(byte)
            return -1 - (4 - len) if len < 4
            return 4 if Enc.surrogate_second?(s.getbyte(p + 3))
          end
          INVALID
        end

        def mbc_newline?(s, p, e) = p + 1 < e && s.getbyte(p) == 0x0a && s.getbyte(p + 1) == 0x00

        def mbc_to_code(s, p, _e)
          c0 = s.getbyte(p)
          c1 = s.getbyte(p + 1)
          if Enc.surrogate_first?(c1)
            ((((c1 << 8) + c0) & 0x03ff) << 10) + (((s.getbyte(p + 3).to_i << 8) + s.getbyte(p + 2).to_i) & 0x03ff) + 0x10000
          else
            (c1 * 256) + c0
          end
        end

        def code_to_mbc(code)
          if code > 0xffff
            high = (code >> 10) + 0xd7c0
            low = (code & 0x3ff) + 0xdc00
            [high & 0xff, (high >> 8) & 0xff, low & 0xff, (low >> 8) & 0xff].pack("C*")
          else
            [code & 0xff, (code & 0xff00) >> 8].pack("C*")
          end
        end

        def mbc_case_fold(_flag, s, p, e)
          if s.getbyte(p) < 0x80 && s.getbyte(p + 1) == 0
            return [[ascii_lower(s.getbyte(p)), 0].pack("C*"), 2]
          end

          unicode_mbc_case_fold(s, p, e)
        end

        def left_adjust_char_head(s, start, p, _e)
          return p if p <= start

          p -= 1 if (p - start).odd?
          p -= 2 if Enc.surrogate_second?(s.getbyte(p + 1)) && p > start + 1
          p
        end

        def kernel_kind = KIND_UTF16LE
      end

      class UTF16BE < UTF16
        def name = "UTF-16BE"

        def precise_len(s, p, e)
          byte = s.getbyte(p)
          unless Enc.surrogate?(byte)
            return e - p >= 2 ? 2 : -1 - 1
          end

          if Enc.surrogate_first?(byte)
            case e - p
            when 1 then return -1 - 3
            when 2 then return -1 - 2
            when 3 then return -1 - 1 if Enc.surrogate_second?(s.getbyte(p + 2))
            else return 4 if Enc.surrogate_second?(s.getbyte(p + 2))
            end
          end
          INVALID
        end

        def mbc_newline?(s, p, e) = p + 1 < e && s.getbyte(p + 1) == 0x0a && s.getbyte(p) == 0x00

        def mbc_to_code(s, p, _e)
          c0 = s.getbyte(p)
          if Enc.surrogate_first?(c0)
            ((((c0 << 8) + s.getbyte(p + 1)) & 0x03ff) << 10) + (((s.getbyte(p + 2).to_i << 8) + s.getbyte(p + 3).to_i) & 0x03ff) + 0x10000
          else
            (c0 * 256) + s.getbyte(p + 1)
          end
        end

        def code_to_mbc(code)
          if code > 0xffff
            high = (code >> 10) + 0xd7c0
            low = (code & 0x3ff) + 0xdc00
            [(high >> 8) & 0xff, high & 0xff, (low >> 8) & 0xff, low & 0xff].pack("C*")
          else
            [(code & 0xff00) >> 8, code & 0xff].pack("C*")
          end
        end

        def mbc_case_fold(_flag, s, p, e)
          if s.getbyte(p + 1) < 0x80 && s.getbyte(p) == 0
            return [[0, ascii_lower(s.getbyte(p + 1))].pack("C*"), 2]
          end

          unicode_mbc_case_fold(s, p, e)
        end

        def left_adjust_char_head(s, start, p, _e)
          return p if p <= start

          p -= 1 if (p - start).odd?
          p -= 2 if Enc.surrogate_second?(s.getbyte(p)) && p > start + 1
          p
        end

        def kernel_kind = KIND_UTF16BE
      end

      # The two UTF-32 encodings.
      class UTF32 < Base
        include UnicodeEncoding

        def max_len = 4
        def min_len = 4
        def sb_out = 0x00
        def code_to_mbclen(_code) = 4
        def allowed_reverse_match?(_s, _p, _e) = false

        def precise_len(s, p, e)
          return INVALID if e < p
          return -1 - (4 - (e - p)) if e - p < 4
          return INVALID unless Enc.valid_codepoint?(mbc_to_code(s, p, e))

          4
        end

        def left_adjust_char_head(_s, start, p, _e)
          return p if p <= start

          p - ((p - start) % 4)
        end
      end

      class UTF32LE < UTF32
        def name = "UTF-32LE"

        def mbc_newline?(s, p, e)
          p + 3 < e && s.getbyte(p) == 0x0a && s.getbyte(p + 1) == 0 && s.getbyte(p + 2) == 0 && s.getbyte(p + 3) == 0
        end

        def mbc_to_code(s, p, _e) = s.byteslice(p, 4).unpack1("V")
        def code_to_mbc(code) = [code & 0xffffffff].pack("V")

        def mbc_case_fold(_flag, s, p, e)
          if s.getbyte(p) < 0x80 && s.getbyte(p + 1) == 0 && s.getbyte(p + 2) == 0 && s.getbyte(p + 3) == 0
            return [[ascii_lower(s.getbyte(p)), 0, 0, 0].pack("C*"), 4]
          end

          unicode_mbc_case_fold(s, p, e)
        end

        def kernel_kind = KIND_UTF32LE
      end

      class UTF32BE < UTF32
        def name = "UTF-32BE"

        def mbc_newline?(s, p, e)
          p + 3 < e && s.getbyte(p + 3) == 0x0a && s.getbyte(p + 2) == 0 && s.getbyte(p + 1) == 0 && s.getbyte(p) == 0
        end

        def mbc_to_code(s, p, _e) = s.byteslice(p, 4).unpack1("N")
        def code_to_mbc(code) = [code & 0xffffffff].pack("N")

        def mbc_case_fold(_flag, s, p, e)
          if s.getbyte(p + 3) < 0x80 && s.getbyte(p + 2) == 0 && s.getbyte(p + 1) == 0 && s.getbyte(p) == 0
            return [[0, 0, 0, ascii_lower(s.getbyte(p + 3))].pack("C*"), 4]
          end

          unicode_mbc_case_fold(s, p, e)
        end

        def kernel_kind = KIND_UTF32BE
      end
    end

    # The Unicode tables as the engine reads them. The generated file
    # contains each as a String. A table is decoded the first time a
    # pattern needs it, so a program that uses no property and no case
    # folding decodes none.
    module Unicode
      @ranges = {}
      @folds = {}

      # Each normalized property keyword to its table index.
      def self.properties
        @properties ||= PROPERTY_NAMES.split(" ").zip(PROPERTY_TABLES.unpack("w*")).to_h.freeze
      end

      def self.table_count = range_ends.size

      def self.range_ends
        @range_ends ||= RANGE_ENDS.unpack("w*").freeze
      end

      # Bit `ctype` of the Latin-1 entry for `code`, under 256.
      def self.ctype_bit?(code, ctype)
        bits = CTYPE_BITS.getbyte(code * 2) | (CTYPE_BITS.getbyte((code * 2) + 1) << 8)
        bits[ctype] == 1
      end

      # The ranges of table `index` as a flat [low, high, ...] Array.
      def self.ranges(index)
        @ranges[index] ||= begin
          ends = range_ends
          from = index.zero? ? 0 : ends[index - 1]
          out = []
          last = -1
          RANGES.byteslice(from, ends[index] - from).unpack("w*").each_slice(2) do |gap, span|
            lo = last + gap + 1
            out << lo << lo + span
            last = lo + span
          end
          out.freeze
        end
      end

      # A fold table as a Hash from its key to the codes it maps to, in
      # the table's order: 0 is CASE_FOLD and 1 to 3 the unfold tables
      # by key width. A one-code key is the Integer, a wider one an Array.
      def self.folds(width)
        @folds[width] ||= begin
          words = [CASE_FOLD, CASE_UNFOLD_1, CASE_UNFOLD_2, CASE_UNFOLD_3][width].unpack("w*")
          keys = width.zero? ? 1 : width
          table = {}
          at = 0
          while at < words.size
            key = keys == 1 ? words[at] : words[at, keys].freeze
            count = words[at + keys]
            table[key] = words[at + keys + 1, count].freeze
            at += keys + 1 + count
          end
          table.freeze
        end
      end

      # onig_is_in_code_range: a binary search of the (low, high) pairs.
      def self.in_code_range?(ranges, code)
        n = ranges.size / 2
        low = 0
        high = n
        while low < high
          x = (low + high) >> 1
          if code > ranges[x * 2 + 1]
            low = x + 1
          else
            high = x
          end
        end
        low < n && code >= ranges[low * 2]
      end

      def self.fold(code) = folds(0)[code]
      def self.unfold1(code) = folds(1)[code]
      def self.unfold2(codes) = folds(2)[codes]
      def self.unfold3(codes) = folds(3)[codes]
    end
  end
end
