# frozen_string_literal: true

# Derived from Onigmo (BSD-2-Clause); see THIRD_PARTY_NOTICES.md.
#
# Onigmo's multibyte encodings past Unicode: EUC-JP (enc/euc_jp.c),
# Shift_JIS and Windows-31J (shift_jis.h), Big5, GBK and CP949 (big5.c,
# gbk.c, cp949.c), EUC-KR (euc_kr.c), EUC-TW (euc_tw.c), GB18030
# (gb18030.c) and Emacs-Mule (emacs_mule.c), with the helpers of
# regenc.c they share (onigenc_mbn_*, onigenc_mb2_*, onigenc_mb4_*). A
# port under the BSD-2-Clause license reproduced in regexp.rb.
class Regexp
  module Onig
    module Enc
      ACCEPT = -1

      # trans[state][byte] of a state table String: -1 accepts, -2 fails.
      def self.trans(table, state, byte)
        v = table.getbyte((state * 256) + byte)
        v >= 128 ? v - 256 : v
      end

      # An encoding whose mbc_enc_len walks a `trans` table from its lead
      # byte: the result for each step's end of text comes from `need`.
      class Automaton < Base
        attr_reader :name

        def initialize(name, tables)
          @name = name
          @len, @trans, @trail = tables
        end

        def min_len = 1

        # mbc_enc_len
        def precise_len(s, p, e)
          first = s.getbyte(p)
          state = Enc.trans(@trans, 0, first)
          k = 1
          loop do
            return state == ACCEPT ? k : INVALID if state < 0
            return INVALID if k == max_len
            return -1 - need(k, first) if p + k == e

            state = Enc.trans(@trans, state, s.getbyte(p + k))
            k += 1
          end
        end

        # ONIGENC_CONSTRUCT_MBCLEN_NEEDMORE's count when the text ends
        # after `k` bytes of a character that started with `first`.
        def need(k, first) = @len.getbyte(first) - k

        # onigenc_mbn_mbc_to_code over `len` bytes (enclen, or
        # mbc_enc_len where the encoding reads it so).
        def mbn_to_code(s, p, e, len)
          n = s.getbyte(p)
          return n if len == 1

          i = 1
          while i < len
            break if p + i >= e

            n = (n << 8) + s.getbyte(p + i)
            i += 1
          end
          n
        end

        def mbc_to_code(s, p, e) = mbn_to_code(s, p, e, enclen(s, p, e))

        # onigenc_mbn_mbc_case_fold
        def mbc_case_fold(_flag, s, p, e)
          c = s.getbyte(p)
          return [ascii_lower(c).chr.b, 1] if c < 0x80

          len = enclen(s, p, e)
          [s.byteslice(p, len), len]
        end

        def apply_all_case_fold(_flag, &block) = ascii_apply_all_case_fold(&block)
        def case_fold_codes_by_str(_flag, s, p, _e) = ascii_case_fold_codes_by_str(s, p)

        # onigenc_mb2_is_code_ctype / onigenc_mb4_is_code_ctype
        def code_ctype?(code, ctype)
          return ascii_code_ctype?(code, ctype) if code < 128
          return code_to_mbclen(code) > 1 if word_graph_print?(ctype)

          false
        end

        # onigenc_mb2_code_to_mbclen
        def mb2_code_to_mbclen(code)
          return 1 if code <= 0xff
          return 2 if code <= 0xffff

          Err::TOO_BIG_WIDE_CHAR_VALUE
        end

        # onigenc_mb4_code_to_mbclen
        def mb4_code_to_mbclen(code)
          if (code & 0xff000000) != 0 then 4
          elsif (code & 0xff0000) != 0 then 3
          elsif (code & 0xff00) != 0 then 2
          else 1
          end
        end

        # onigenc_mb2_code_to_mbc
        def mb2_code_to_mbc(code)
          bytes = []
          bytes << ((code >> 8) & 0xff) if (code & 0xff00) != 0
          bytes << (code & 0xff)
          checked(bytes.pack("C*"))
        end

        # onigenc_mb4_code_to_mbc
        def mb4_code_to_mbc(code)
          bytes = []
          bytes << ((code >> 24) & 0xff) if (code & 0xff000000) != 0
          bytes << ((code >> 16) & 0xff) if (code & 0xff0000) != 0 || !bytes.empty?
          bytes << ((code >> 8) & 0xff) if (code & 0xff00) != 0 || !bytes.empty?
          bytes << (code & 0xff)
          checked(bytes.pack("C*"))
        end

        # The `enclen(enc, buf, p) != (p - buf)` check of the code_to_mbc
        # helpers.
        def checked(buf)
          raise Error.new(Err::INVALID_CODE_POINT_VALUE) if enclen(buf, 0, buf.bytesize) != buf.bytesize

          buf
        end

        # The tail that every left_adjust_char_head of these encodings
        # shares: from the head that `q` found, the character there if it
        # contains `p`, else the even offset past it.
        def adjust_tail(p, q, len)
          return q if q + len > p

          q += len
          q + ((p - q) & ~1)
        end

        def kernel_tables = { len: @len, trans: @trans, trail: @trail }
      end

      # The JIS properties of EUC-JP, Shift_JIS and Windows-31J
      # (enc/jis/props.h): six names past the POSIX ones, each a table of
      # code ranges in the encoding's own codes.
      module JIS
        KEYWORDS = %w[hiragana katakana han latin greek cyrillic].freeze

        # The tables as flat [low, high, ...] Arrays.
        def self.ranges(tables) = tables.map { |table| table.unpack("V*").drop(1).freeze }.freeze

        # onig_jis_property: the name's bytes, as they are, matched
        # without regard to ASCII case.
        def property_name_to_ctype(s, p, e, reader = self)
          name = s.byteslice(p, e - p)
          if name.bytesize.between?(3, 8)
            lowered = name.bytes.map { |b| ascii_lower(b) }.pack("C*")
            i = KEYWORDS.index(lowered)
            return CType::MAX_STD + 1 + i if i
          end
          minimum_property_name_to_ctype(s, p, e, reader)
        end

        def jis_ranges(ctype)
          index = ctype - (CType::MAX_STD + 1)
          raise Error.new(Err::TYPE_BUG) if index >= @props.size

          @props[index]
        end

        def code_ctype?(code, ctype)
          if ctype <= CType::MAX_STD
            return ascii_code_ctype?(code, ctype) if code < 128
            return wide_word?(code) if word_graph_print?(ctype)

            false
          else
            Unicode.in_code_range?(jis_ranges(ctype), code)
          end
        end

        def wide_word?(code) = code_to_mbclen(code) > 1

        # get_ctype_code_range: [sb_out, ranges], nil for the POSIX types.
        def ctype_code_range(ctype)
          return nil if ctype <= CType::MAX_STD

          [0x80, jis_ranges(ctype)]
        end

        # get_case_fold_codes_by_str
        def case_fold_codes_by_str(_flag, s, p, e)
          code = mbc_to_code(s, p, e)
          return ascii_case_fold_codes_by_str(s, p) if code < 0x80

          len = precise_len(s, p, e)
          lower = lower_case(code)
          upper = upper_case(code)
          if code != lower then [[len, [lower]]]
          elsif code != upper then [[len, [upper]]]
          else []
          end
        end
      end

      # EUC-JP
      class EUCJP < Automaton
        include JIS

        def initialize
          super("EUC-JP", EncTables::EUC_JP)
          @props = JIS.ranges(EncTables::EUC_JP_PROPS)
          @folds = EncTables::EUC_JP_FOLDS.unpack("V*")
        end

        def max_len = 3

        def mbc_to_code(s, p, e) = mbn_to_code(s, p, e, precise_len(s, p, e))

        def code_to_mbclen(code)
          if code < 0x80 then 1
          elsif code > 0x00ffffff then Err::TOO_BIG_WIDE_CHAR_VALUE
          elsif (code & 0xff808080) == 0x00808080 then 3
          elsif (code & 0xffff8080) == 0x00008080 then 2
          else Err::INVALID_CODE_POINT_VALUE
          end
        end

        # code_to_mbc: the bytes, or the error code when they are not one
        # character.
        def raw_code_to_mbc(code)
          bytes = []
          bytes << ((code >> 16) & 0xff) if (code & 0xff0000) != 0
          bytes << ((code >> 8) & 0xff) if (code & 0xff00) != 0
          bytes << (code & 0xff)
          buf = bytes.pack("C*")
          precise_len(buf, 0, buf.bytesize) == buf.bytesize ? buf : Err::INVALID_CODE_POINT_VALUE
        end

        def code_to_mbc(code)
          buf = raw_code_to_mbc(code)
          raise Error.new(buf) if buf.is_a?(Integer)

          buf
        end

        def lower_case(code)
          if code >= 0xa3c1 && code <= 0xa3da then code + 0x20
          elsif code >= 0xa6a1 && code <= 0xa6b8 then code + 0x20
          elsif code >= 0xa7a1 && code <= 0xa7c1 then code + 0x30
          else code
          end
        end

        def upper_case(code)
          if code >= 0xa3e1 && code <= 0xa3fa then code - 0x20
          elsif code >= 0xa6c1 && code <= 0xa6d8 then code - 0x20
          elsif code >= 0xa7d1 && code <= 0xa7f1 then code - 0x30
          else code
          end
        end

        # mbc_case_fold: a character that folds to no character is read
        # as its first byte.
        def mbc_case_fold(_flag, s, p, e)
          c = s.getbyte(p)
          return [ascii_lower(c).chr.b, 1] if c < 0x80

          code = lower_case(mbc_to_code(s, p, e))
          bytes = []
          bytes << ((code >> 16) & 0xff) if (code & 0xff0000) != 0
          bytes << ((code >> 8) & 0xff) if (code & 0xff00) != 0
          bytes << (code & 0xff)
          buf = bytes.pack("C*")
          buf = buf.byteslice(0, 1) unless precise_len(buf, 0, buf.bytesize) == buf.bytesize
          [buf, buf.bytesize]
        end

        def apply_all_case_fold(_flag, &block) = apply_all_case_fold_with_map(@folds, false, &block)

        def left_adjust_char_head(s, start, p, e)
          return p if p <= start

          q = p
          q -= 1 while !eucjp_lead?(s.getbyte(q)) && q > start
          adjust_tail(p, q, precise_len(s, q, e))
        end

        # eucjp_islead
        def eucjp_lead?(c) = ((c - 0xa1) & 0xff) > 0xfe - 0xa1

        def allowed_reverse_match?(s, p, _e)
          c = s.getbyte(p)
          c <= 0x7e || c == 0x8e || c == 0x8f
        end

        def kernel_kind = KIND_EUC_JP
      end

      # Shift_JIS and Windows-31J, which differ in their Han table.
      class ShiftJIS < Automaton
        include JIS

        def initialize(name, props)
          super(name, EncTables::SHIFT_JIS)
          @props = JIS.ranges(props)
          @folds = EncTables::SHIFT_JIS_FOLDS.unpack("V*")
        end

        def max_len = 2

        def mbc_to_code(s, p, e) = mbn_to_code(s, p, e, precise_len(s, p, e))

        def code_to_mbclen(code)
          if code < 256
            @len.getbyte(code) == 1 ? 1 : Err::INVALID_CODE_POINT_VALUE
          elsif code <= 0xffff
            @trail.getbyte(code & 0xff) != 0 ? 2 : Err::INVALID_CODE_POINT_VALUE
          else
            Err::TOO_BIG_WIDE_CHAR_VALUE
          end
        end

        def code_to_mbc(code)
          bytes = []
          bytes << ((code >> 8) & 0xff) if (code & 0xff00) != 0
          bytes << (code & 0xff)
          bytes.pack("C*")
        end

        def lower_case(code)
          if code >= 0x8260 && code <= 0x8279 then code + 0x21
          elsif code >= 0x839f && code <= 0x83b6 then code + 0x20
          elsif code >= 0x8440 && code <= 0x8460 then code + 0x30 + (code >= 0x844f ? 1 : 0)
          else code
          end
        end

        def upper_case(code)
          if code >= 0x8281 && code <= 0x829a then code - 0x21
          elsif code >= 0x83bf && code <= 0x83d6 then code - 0x20
          elsif (code >= 0x8470 && code <= 0x847e) || (code >= 0x8480 && code <= 0x8491)
            code - (0x30 - (code >= 0x8480 ? 1 : 0))
          else code
          end
        end

        def mbc_case_fold(_flag, s, p, e)
          c = s.getbyte(p)
          return [ascii_lower(c).chr.b, 1] if c < 0x80

          buf = code_to_mbc(lower_case(mbc_to_code(s, p, e)))
          [buf, buf.bytesize]
        end

        def apply_all_case_fold(_flag, &block) = apply_all_case_fold_with_map(@folds, false, &block)

        # is_code_ctype: every code past ASCII is a word, graph and print
        # character.
        def wide_word?(_code) = true

        def left_adjust_char_head(s, start, p, e)
          return p if p <= start

          q = p
          if @trail.getbyte(s.getbyte(q)) != 0
            while q > start
              q -= 1
              unless @len.getbyte(s.getbyte(q)) > 1
                q += 1
                break
              end
            end
          end
          adjust_tail(p, q, precise_len(s, q, e))
        end

        def allowed_reverse_match?(s, p, _e) = @trail.getbyte(s.getbyte(p)) == 0

        def kernel_kind = KIND_SHIFT_JIS
      end

      # Big5 (and the Big5-HKSCS and Big5-UAO that read as it), GBK and
      # CP949: two-byte encodings whose left_adjust_char_head steps back
      # over trail bytes.
      class Trail < Automaton
        def max_len = 2
        def need(_k, first) = @len.getbyte(first) - 1
        def code_to_mbclen(code) = mb2_code_to_mbclen(code)
        def code_to_mbc(code) = mb2_code_to_mbc(code)

        def left_adjust_char_head(s, start, p, e)
          return p if p <= start

          q = p
          if @trail.getbyte(s.getbyte(q)) != 0
            while q > start
              q -= 1
              unless @len.getbyte(s.getbyte(q)) > 1
                q += 1
                break
              end
            end
          end
          adjust_tail(p, q, enclen(s, q, e))
        end

        def allowed_reverse_match?(s, p, _e) = @trail.getbyte(s.getbyte(p)) == 0

        def kernel_kind = KIND_TRAIL
      end

      # EUC-KR, and GB2312 and GB12345 that read as it.
      class EUCKR < Automaton
        def initialize = super("EUC-KR", EncTables::EUC_KR)
        def max_len = 2
        def need(_k, first) = @len.getbyte(first) - 1
        def code_to_mbclen(code) = mb2_code_to_mbclen(code)
        def code_to_mbc(code) = mb2_code_to_mbc(code)

        def left_adjust_char_head(s, start, p, e)
          return p if p <= start

          q = p
          q -= 1 while !euckr_lead?(s.getbyte(q)) && q > start
          adjust_tail(p, q, enclen(s, q, e))
        end

        # euckr_islead
        def euckr_lead?(c) = c < 0xa1 || c == 0xff

        def allowed_reverse_match?(s, p, _e) = s.getbyte(p) <= 0x7e

        def kernel_kind = KIND_EUC_KR
      end

      # EUC-TW
      class EUCTW < Automaton
        def initialize = super("EUC-TW", EncTables::EUC_TW)
        def max_len = 4
        def need(k, first) = k == 1 ? @len.getbyte(first) - 1 : 4 - k
        def code_to_mbclen(code) = mb4_code_to_mbclen(code)
        def code_to_mbc(code) = mb4_code_to_mbc(code)

        def left_adjust_char_head(s, start, p, e)
          return p if p <= start

          q = p
          q -= 1 while !euctw_lead?(s.getbyte(q)) && q > start
          adjust_tail(p, q, enclen(s, q, e))
        end

        # euctw_islead
        def euctw_lead?(c) = ((c - 0xa1) & 0xff) > 0xfe - 0xa1

        def allowed_reverse_match?(s, p, _e) = s.getbyte(p) <= 0x7e

        def kernel_kind = KIND_EUC_TW
      end

      # GB18030
      class GB18030 < Automaton
        C1 = 0
        C2 = 1
        C4 = 2
        CM = 3

        def initialize
          super("GB18030", EncTables::GB18030)
          @map = @len
        end

        def max_len = 4
        def need(k, _first) = k == 1 ? 1 : 4 - k
        def code_to_mbclen(code) = mb4_code_to_mbclen(code)
        def code_to_mbc(code) = mb4_code_to_mbc(code)
        def allowed_reverse_match?(s, p, _e) = @map.getbyte(s.getbyte(p)) == C1

        # The states of gb18030_left_adjust_char_head, in its order.
        S_START = 0
        S_ONE_C2 = 1
        S_ONE_C4 = 2
        S_ONE_CM = 3
        S_ODD_CM_ONE_CX = 4
        S_EVEN_CM_ONE_CX = 5
        S_ONE_CMC4 = 6
        S_ODD_CMC4 = 7
        S_ONE_C4_ODD_CMC4 = 8
        S_EVEN_CMC4 = 9
        S_ONE_C4_EVEN_CMC4 = 10
        S_ODD_CM_ODD_CMC4 = 11
        S_EVEN_CM_ODD_CMC4 = 12
        S_ODD_CM_EVEN_CMC4 = 13
        S_EVEN_CM_EVEN_CMC4 = 14
        S_ODD_C4CM = 15
        S_ONE_CM_ODD_C4CM = 16
        S_EVEN_C4CM = 17
        S_ONE_CM_EVEN_C4CM = 18
        S_EVEN_CM_ODD_C4CM = 19
        S_ODD_CM_ODD_C4CM = 20
        S_EVEN_CM_EVEN_C4CM = 21
        S_ODD_CM_EVEN_C4CM = 22

        # For each state, what each byte class (C1, C2, C4, CM) does: a
        # state to move to, or [:back, n] to return the position n bytes
        # before the given one.
        MOVES = [
          [[:back, 0], S_ONE_C2, S_ONE_C4, S_ONE_CM],
          [[:back, 0], [:back, 0], [:back, 0], S_ODD_CM_ONE_CX],
          [[:back, 0], [:back, 0], [:back, 0], S_ONE_CMC4],
          [[:back, 0], [:back, 0], S_ODD_C4CM, S_ODD_CM_ONE_CX],
          [[:back, 1], [:back, 1], [:back, 1], S_EVEN_CM_ONE_CX],
          [[:back, 0], [:back, 0], [:back, 0], S_ODD_CM_ONE_CX],
          [[:back, 1], [:back, 1], S_ONE_C4_ODD_CMC4, S_EVEN_CM_ONE_CX],
          [[:back, 1], [:back, 1], S_ONE_C4_ODD_CMC4, S_ODD_CM_ODD_CMC4],
          [[:back, 1], [:back, 1], [:back, 1], S_EVEN_CMC4],
          [[:back, 3], [:back, 3], S_ONE_C4_EVEN_CMC4, S_ODD_CM_EVEN_CMC4],
          [[:back, 3], [:back, 3], [:back, 3], S_ODD_CMC4],
          [[:back, 3], [:back, 3], [:back, 3], S_EVEN_CM_ODD_CMC4],
          [[:back, 1], [:back, 1], [:back, 1], S_ODD_CM_ODD_CMC4],
          [[:back, 1], [:back, 1], [:back, 1], S_EVEN_CM_EVEN_CMC4],
          [[:back, 3], [:back, 3], [:back, 3], S_ODD_CM_EVEN_CMC4],
          [[:back, 0], [:back, 0], [:back, 0], S_ONE_CM_ODD_C4CM],
          [[:back, 2], [:back, 2], S_EVEN_C4CM, S_EVEN_CM_ODD_C4CM],
          [[:back, 2], [:back, 2], [:back, 2], S_ONE_CM_EVEN_C4CM],
          [[:back, 0], [:back, 0], S_ODD_C4CM, S_EVEN_CM_EVEN_C4CM],
          [[:back, 0], [:back, 0], [:back, 0], S_ODD_CM_ODD_C4CM],
          [[:back, 2], [:back, 2], [:back, 2], S_EVEN_CM_ODD_C4CM],
          [[:back, 2], [:back, 2], [:back, 2], S_ODD_CM_EVEN_C4CM],
          [[:back, 0], [:back, 0], [:back, 0], S_EVEN_CM_EVEN_C4CM],
        ].freeze

        # What each state returns when the text runs out, as bytes back.
        AT_START = [0, 0, 0, 0, 1, 0, 1, 1, 1, 3, 3, 3, 1, 1, 3, 0, 2, 2, 0, 0, 2, 2, 0].freeze

        # gb18030_left_adjust_char_head
        def left_adjust_char_head(s, start, p, _e)
          state = S_START
          q = p
          while q >= start
            move = MOVES[state][@map.getbyte(s.getbyte(q))]
            return p - move[1] if move.is_a?(Array)

            state = move
            q -= 1
          end
          p - AT_START[state]
        end

        def kernel_kind = KIND_GB18030
        def kernel_tables = { map: @map, trans: @trans }
      end

      # Emacs-Mule, and stateless-ISO-2022-JP that reads as it.
      class EmacsMule < Automaton
        def initialize = super("Emacs-Mule", EncTables::EMACS_MULE)
        def max_len = 4

        def code_to_mbclen(code)
          if code < 0x80 then 1
          elsif (code & 0xff000000) >= 0x80000000 then 4
          elsif (code & 0xff0000) >= 0x800000 then 3
          elsif (code & 0xff00) >= 0x8000 then 2
          else Err::INVALID_CODE_POINT_VALUE
          end
        end

        def code_to_mbc(code)
          bytes = []
          bytes << ((code >> 24) & 0xff) if (code & 0xff000000) != 0
          bytes << ((code >> 16) & 0xff) if (code & 0xff0000) != 0
          bytes << ((code >> 8) & 0xff) if (code & 0xff00) != 0
          bytes << (code & 0xff)
          checked(bytes.pack("C*"))
        end

        # mbc_case_fold: the bytes mbc_enc_len counts, as they are.
        def mbc_case_fold(_flag, s, p, e)
          c = s.getbyte(p)
          return [ascii_lower(c).chr.b, 1] if c < 0x80

          len = precise_len(s, p, e)
          [len > 0 ? s.byteslice(p, len) : "".b, len]
        end

        # is_code_ctype: any code past ASCII of more than a byte is of
        # every type.
        def code_ctype?(code, ctype)
          return ascii_code_ctype?(code, ctype) if code < 128

          code_to_mbclen(code) > 1
        end

        def left_adjust_char_head(s, start, p, _e)
          return p if p <= start

          p -= 1 while s.getbyte(p) >= 0x9e && p > start
          p
        end

        def kernel_kind = KIND_EMACS_MULE
      end
    end
  end
end
