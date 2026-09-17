# The two encodings ruby hands Onigmo (OnigEncodingType): UTF-8 for a
# Unicode subject (enc/utf_8.c, enc/unicode.c) and ASCII, the bytewise
# one every other encoding matches under (enc/ascii.c, regenc.c). A
# pattern or subject is a binary String and a position is a byte
# offset into it. A port under the BSD-2-Clause license reproduced in
# regexp.rb.
class Regexp
  module Onig
    module Enc
      # The shared helpers of regenc.c, over the per-encoding primitives.
      class Base
        # onigenc_mbclen: the length of the character at `p`, cut at
        # `e`; an invalid byte counts one.
        def len(s, p, e)
          ret = precise_len(s, p, e)
          if ret > 0
            ret = e - p if p + ret > e
            ret
          elsif ret < -1
            e - p
          else
            p < e ? 1 : 0
          end
        end

        # onigenc_mbclen_approximate: the length the lead byte announces
        # even past `e`.
        def len_approx(s, p, e)
          ret = precise_len(s, p, e)
          if ret > 0 then ret
          elsif ret < -1 then (e - p) + (-1 - ret)
          else 1
          end
        end

        # enclen (regenc.h:94)
        def enclen(s, p, e) = max_len == min_len ? (p < e ? min_len : 0) : len(s, p, e)

        def right_adjust_char_head(s, start, p, e)
          q = left_adjust_char_head(s, start, p, e)
          q += enclen(s, q, e) if q < p
          q
        end

        def prev_char_head(s, start, p, e)
          return nil if p <= start

          left_adjust_char_head(s, start, p - 1, e)
        end

        def step_back(s, start, p, e, n)
          while !p.nil? && n > 0
            n -= 1
            return nil if p <= start

            p = left_adjust_char_head(s, start, p - 1, e)
          end
          p
        end

        def step(s, p, e, n)
          q = p
          n.times { q += len(s, q, e) }
          q <= e ? q : nil
        end

        def strlen(s, p, e)
          n = 0
          q = p
          while q < e
            q += len(s, q, e)
            n += 1
          end
          n
        end

        # onigenc_with_ascii_strncmp: `sascii` (ASCII bytes) against the
        # next `n` characters at `p`; 0 when they agree.
        def with_ascii_strncmp(s, p, e, sascii, n)
          n.times do |i|
            return sascii.getbyte(i) if p >= e

            x = sascii.getbyte(i) - mbc_to_code(s, p, e)
            return x if x != 0

            p += enclen(s, p, e)
          end
          0
        end

        def with_ascii_strnicmp(s, p, e, sascii, n)
          n.times do |i|
            return sascii.getbyte(i) if p >= e

            c = ascii_lower(mbc_to_code(s, p, e))
            x = ascii_lower(sascii.getbyte(i)) - c
            return x if x != 0

            p += enclen(s, p, e)
          end
          0
        end

        # ONIGENC_ASCII_CODE_TO_LOWER_CASE, for a code under 256.
        def ascii_lower(c) = c >= 0x41 && c <= 0x5a ? c + 0x20 : c

        def ascii_code_ctype?(code, ctype) = code < 128 && Unicode.ctype_bit?(code, ctype)

        def mbc_word?(s, p, e) = code_ctype?(mbc_to_code(s, p, e), CType::WORD)
        def mbc_ascii_word?(s, p, e) = ascii_code_ctype?(mbc_to_code(s, p, e), CType::WORD)
        def mbc_newline?(s, p, e) = p < e && s.getbyte(p) == 0x0a
        def allowed_reverse_match?(_s, _p, _e) = true
        def singlebyte? = max_len == 1
      end

      # OnigEncodingASCII: one byte per character, ASCII case folding,
      # the fourteen POSIX property names and nothing more.
      class ASCII < Base
        def name = "ASCII-8BIT"
        def max_len = 1
        def min_len = 1
        def unicode? = false

        def precise_len(_s, _p, _e) = 1
        def mbc_to_code(s, p, _e) = s.getbyte(p)
        def code_to_mbclen(code) = code > 0xff ? Err::INVALID_CODE_POINT_VALUE : 1

        def code_to_mbc(code)
          raise Error.new(Err::INVALID_CODE_POINT_VALUE) if code > 0xff

          (code & 0xff).chr.b
        end

        def left_adjust_char_head(_s, _start, p, _e) = p
        def code_ctype?(code, ctype) = ascii_code_ctype?(code, ctype)
        def ctype_code_range(_ctype) = nil

        # onigenc_ascii_mbc_case_fold: [the folded bytes, the bytes read]
        def mbc_case_fold(_flag, s, p, _e) = [ascii_lower(s.getbyte(p)).chr.b, 1]

        # onigenc_ascii_apply_all_case_fold
        def apply_all_case_fold(_flag)
          (0x41..0x5a).each do |upper|
            lower = upper + 0x20
            yield upper, [lower]
            yield lower, [upper]
          end
        end

        # onigenc_ascii_get_case_fold_codes_by_str: [[byte length, codes]]
        def case_fold_codes_by_str(_flag, s, p, _e)
          c = s.getbyte(p)
          if c >= 0x41 && c <= 0x5a then [[1, [c + 0x20]]]
          elsif c >= 0x61 && c <= 0x7a then [[1, [c - 0x20]]]
          else []
          end
        end

        # onigenc_minimum_property_name_to_ctype
        MINIMUM_PROPERTIES = {
          "Alnum" => CType::ALNUM, "Alpha" => CType::ALPHA, "Blank" => CType::BLANK,
          "Cntrl" => CType::CNTRL, "Digit" => CType::DIGIT, "Graph" => CType::GRAPH,
          "Lower" => CType::LOWER, "Print" => CType::PRINT, "Punct" => CType::PUNCT,
          "Space" => CType::SPACE, "Upper" => CType::UPPER, "XDigit" => CType::XDIGIT,
          "ASCII" => CType::ASCII, "Word" => CType::WORD,
        }.freeze

        def property_name_to_ctype(s, p, e)
          len = strlen(s, p, e)
          MINIMUM_PROPERTIES.each do |name, ctype|
            return ctype if len == name.bytesize && with_ascii_strnicmp(s, p, e, name, name.bytesize) == 0
          end
          Err::INVALID_CHAR_PROPERTY_NAME
        end
      end

      # OnigEncodingUTF_8 with Unicode 17.0's tables.
      class UTF8 < Base
        INVALID_CODE_FE = 0xfffffffe
        INVALID_CODE_FF = 0xffffffff
        VALID_CODE_LIMIT = 0x10ffff
        PROPERTY_NAME_MAX_SIZE = 46

        def name = "UTF-8"
        def max_len = 4
        def min_len = 1
        def unicode? = true

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

        # onigenc_unicode_is_code_ctype
        def code_ctype?(code, ctype)
          return Unicode.ctype_bit?(code, ctype) if ctype <= CType::MAX_STD && code < 256
          raise Error.new(Err::TYPE_BUG) if ctype >= Unicode.table_count

          Unicode.in_code_range?(Unicode.ranges(ctype), code)
        end

        # get_ctype_code_range: [sb_out, ranges]
        def ctype_code_range(ctype)
          raise Error.new(Err::TYPE_BUG) if ctype >= Unicode.table_count

          [0x80, Unicode.ranges(ctype)]
        end

        # onigenc_unicode_property_name_to_ctype: the name with spaces,
        # hyphens and underscores dropped and lowercased, looked up.
        def property_name_to_ctype(s, p, e)
          buf = +""
          while p < e
            code = mbc_to_code(s, p, e)
            p += enclen(s, p, e)
            next if code == 0x20 || code == 0x2d || code == 0x5f
            return Err::INVALID_CHAR_PROPERTY_NAME if code >= 0x80

            buf << ascii_lower(code).chr
            return Err::INVALID_CHAR_PROPERTY_NAME if buf.size >= PROPERTY_NAME_MAX_SIZE
          end
          Unicode.properties.fetch(buf, Err::INVALID_CHAR_PROPERTY_NAME)
        end

        # utf_8.c mbc_case_fold over onigenc_unicode_mbc_case_fold
        def mbc_case_fold(_flag, s, p, e)
          byte = s.getbyte(p)
          return [ascii_lower(byte).chr.b, 1] if byte < 128

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

      ASCII_ENC = ASCII.new.freeze
      UTF8_ENC = UTF8.new.freeze
    end

    # The Unicode tables as the engine reads them. The generated file
    # holds each as a String; a table is decoded the first time a
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
