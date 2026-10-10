# frozen_string_literal: true

# Onigmo's tokenizer: fetch_token and fetch_token_in_cc with the
# scanners they use (regparse.c:1837-4195). A port under the
# BSD-2-Clause license reproduced in regexp.rb.
#
# Every scanner takes its start position and returns its stop position,
# as the C's `UChar** src` does. When the C leaves `*src` unchanged on
# some outcome, the scanner returns the position it was given.
class Regexp
  module Onig
    # OnigToken: what fetch_token found. `c` and `code` are one field,
    # as the C's union makes them.
    class Token
      EOT = 0
      RAW_BYTE = 1
      CHAR = 2
      STRING = 3
      CODE_POINT = 4
      ANYCHAR = 5
      CHAR_TYPE = 6
      BACKREF = 7
      CALL = 8
      ANCHOR = 9
      OP_REPEAT = 10
      INTERVAL = 11
      ANYCHAR_ANYTIME = 12
      ALT = 13
      SUBEXP_OPEN = 14
      SUBEXP_CLOSE = 15
      CC_OPEN = 16
      QUOTE_OPEN = 17
      CHAR_PROPERTY = 18
      LINEBREAK = 19
      EXTENDED_GRAPHEME_CLUSTER = 20
      KEEP = 21
      CC_CLOSE = 22
      CC_RANGE = 23
      POSIX_BRACKET_OPEN = 24
      CC_AND = 25
      CC_CC_OPEN = 26

      attr_accessor :type, :escaped, :base, :backp, :c,
                    :anchor_subtype, :anchor_ascii_range,
                    :repeat_lower, :repeat_upper, :repeat_greedy, :repeat_possessive,
                    :backref_num, :backref_ref1, :backref_refs, :backref_by_name,
                    :backref_exist_level, :backref_level,
                    :call_name, :call_gnum, :call_rel,
                    :prop_ctype, :prop_not

      def initialize
        @type = EOT
        @escaped = false
        @base = 0
        @c = 0
      end

      alias code c
      alias code= c=
    end

    module Lexer
      PEND_VALUE = 0

      # PEND, PPEEK, PFETCH: reading the pattern's characters.
      def pend?(p) = p >= @end
      def ppeek(p) = p < @end ? @enc.mbc_to_code(@pat, p, @end) : PEND_VALUE
      def code_at(p) = @enc.max_len == 1 ? @pat.getbyte(p) : @enc.mbc_to_code(@pat, p, @end)
      def pinc(p) = p + @enc.enclen(@pat, p, @end)
      def digit?(c) = @enc.code_ctype?(c, CType::DIGIT)
      def xdigit?(c) = @enc.code_ctype?(c, CType::XDIGIT)

      # XDIGITVAL
      def xdigit_val(c)
        if digit?(c) then c - 0x30
        elsif @enc.code_ctype?(c, CType::UPPER) then c - 0x41 + 10
        else c - 0x61 + 10
        end
      end

      # onig_scan_unsigned_number: [the number (-1 on overflow), the position after it]
      def scan_unsigned_number(p)
        num = 0
        until pend?(p)
          c = code_at(p)
          break unless digit?(c)

          val = c - 0x30
          return [-1, p] if (INT_MAX_LIMIT - val) / 10 < num

          num = num * 10 + val
          p = pinc(p)
        end
        [num, p]
      end

      # scan_unsigned_hexadecimal_number: -1 on overflow, -2 for too few digits
      def scan_unsigned_hexadecimal_number(p, minlen, maxlen)
        restlen = maxlen - minlen
        num = 0
        while !pend?(p) && maxlen != 0
          maxlen -= 1
          c = code_at(p)
          if xdigit?(c)
            val = xdigit_val(c)
            return [-1, p] if (INT_MAX_LIMIT - val) / 16 < num

            num = (num << 4) + val
            p = pinc(p)
          else
            maxlen += 1
            break
          end
        end
        return [-2, p] if maxlen > restlen

        [num, p]
      end

      def scan_unsigned_octal_number(p, maxlen)
        num = 0
        while !pend?(p) && maxlen != 0
          maxlen -= 1
          c = code_at(p)
          if digit?(c) && c < 0x38
            val = c - 0x30
            return [-1, p] if (INT_MAX_LIMIT - val) / 8 < num

            num = (num << 3) + val
            p = pinc(p)
          else
            break
          end
        end
        [num, p]
      end

      # conv_backslash_value
      def conv_backslash_value(c)
        if Syntax.op?(Syntax::OP_ESC_CONTROL_CHARS)
          case c
          when 0x6e then return 0x0a # n
          when 0x74 then return 0x09 # t
          when 0x72 then return 0x0d # r
          when 0x66 then return 0x0c # f
          when 0x61 then return 0x07 # a
          when 0x62 then return 0x08 # b
          when 0x65 then return 0x1b # e
          when 0x76 then return 0x0b if Syntax.op2?(Syntax::OP2_ESC_V_VTAB) # v
          else
            @env.unknown_esc_warn(c) if (c >= 0x61 && c <= 0x7a) || (c >= 0x41 && c <= 0x5a)
          end
        end
        c
      end

      # fetch_range_quantifier: [r, p]; r is 0 for {n,m}, 2 for {n},
      # 1 for "not an interval after all" (p unchanged then).
      def fetch_range_quantifier(p, tok)
        start = p
        syn_allow = Syntax.bv?(Syntax::ALLOW_INVALID_INTERVAL)
        non_low = false

        if pend?(p)
          return [1, start] if syn_allow

          raise Error.new(Err::END_PATTERN_AT_LEFT_BRACE)
        end

        unless syn_allow
          c = ppeek(p)
          raise Error.new(Err::END_PATTERN_AT_LEFT_BRACE) if c == 0x29 || c == 0x28 || c == 0x7c
        end

        low, p = scan_unsigned_number(p)
        raise Error.new(Err::TOO_BIG_NUMBER_FOR_REPEAT_RANGE) if low < 0
        raise Error.new(Err::TOO_BIG_NUMBER_FOR_REPEAT_RANGE) if low > MAX_REPEAT_NUM

        if p == start # can't read low
          return invalid_interval(syn_allow, start) unless Syntax.bv?(Syntax::ALLOW_INTERVAL_LOW_ABBREV)

          low = 0
          non_low = true
        end

        return invalid_interval(syn_allow, start) if pend?(p)

        c = code_at(p)
        p = pinc(p)
        r = 0
        if c == 0x2c
          prev = p
          up, p = scan_unsigned_number(p)
          raise Error.new(Err::TOO_BIG_NUMBER_FOR_REPEAT_RANGE) if up < 0
          raise Error.new(Err::TOO_BIG_NUMBER_FOR_REPEAT_RANGE) if up > MAX_REPEAT_NUM

          if p == prev
            return invalid_interval(syn_allow, start) if non_low

            up = REPEAT_INFINITE # {n,} : {n,infinite}
          end
        else
          return invalid_interval(syn_allow, start) if non_low

          p = prev_of(p, c) # PUNFETCH
          up = low # {n} : exact n times
          r = 2
        end

        return invalid_interval(syn_allow, start) if pend?(p)

        c = code_at(p)
        p = pinc(p)
        if Syntax.op?(Syntax::OP_ESC_BRACE_INTERVAL)
          return invalid_interval(syn_allow, start) if c != Syntax::ESC
          return invalid_interval(syn_allow, start) if pend?(p)

          c = code_at(p)
          p = pinc(p)
        end
        return invalid_interval(syn_allow, start) if c != 0x7d

        raise Error.new(Err::UPPER_SMALLER_THAN_LOWER_IN_REPEAT_RANGE) if up != REPEAT_INFINITE && low > up

        tok.type = Token::INTERVAL
        tok.repeat_lower = low
        tok.repeat_upper = up
        [r, p]
      end

      def invalid_interval(syn_allow, start)
        return [1, start] if syn_allow

        raise Error.new(Err::INVALID_REPEAT_RANGE_PATTERN)
      end

      # PUNFETCH: the position before the character `c` was read at `p`.
      def prev_of(p, _c) = @enc.prev_char_head(@pat, 0, p, @end)

      # fetch_escaped_value: \M-, \C-, \c, or \...; [the code, the position after]
      def fetch_escaped_value(p)
        raise Error.new(Err::END_PATTERN_AT_ESCAPE) if pend?(p)

        c = code_at(p)
        p = pinc(p)
        case c
        when 0x4d # M
          if Syntax.op2?(Syntax::OP2_ESC_CAPITAL_M_BAR_META)
            raise Error.new(Err::END_PATTERN_AT_META) if pend?(p)

            c = code_at(p)
            p = pinc(p)
            raise Error.new(Err::META_CODE_SYNTAX) if c != 0x2d
            raise Error.new(Err::END_PATTERN_AT_META) if pend?(p)

            c = code_at(p)
            p = pinc(p)
            c, p = fetch_escaped_value(p) if c == Syntax::ESC
            c = (c & 0xff) | 0x80
          else
            c = conv_backslash_value(c)
          end
        when 0x43 # C
          if Syntax.op2?(Syntax::OP2_ESC_CAPITAL_C_BAR_CONTROL)
            raise Error.new(Err::END_PATTERN_AT_CONTROL) if pend?(p)

            c = code_at(p)
            p = pinc(p)
            raise Error.new(Err::CONTROL_CODE_SYNTAX) if c != 0x2d

            c, p = fetch_control(p)
          else
            c = conv_backslash_value(c)
          end
        when 0x63 # c
          if Syntax.op?(Syntax::OP_ESC_C_CONTROL)
            c, p = fetch_control(p)
          else
            c = conv_backslash_value(c)
          end
        else
          c = conv_backslash_value(c)
        end
        [c, p]
      end

      # the `control:` label of fetch_escaped_value
      def fetch_control(p)
        raise Error.new(Err::END_PATTERN_AT_CONTROL) if pend?(p)

        c = code_at(p)
        p = pinc(p)
        if c == 0x3f
          c = 0x7f
        else
          c, p = fetch_escaped_value(p) if c == Syntax::ESC
          c &= 0x9f
        end
        [c, p]
      end

      def name_end_code_point(start)
        case start
        when 0x3c then 0x3e   # < >
        when 0x27 then 0x27   # ' '
        when 0x28 then 0x29   # ( )
        when 0x7b then 0x7d   # { }
        else 0
        end
      end

      # ONIGENC_IS_CODE_NAME is TRUE under RUBY: any character can be in a group name.
      def code_name?(_c) = true

      # fetch_name_with_level: \k<name+n>, \k<name-n>, \k<num+n>, \k<-num+n>;
      # [exist_level (1 or 0), name (bytes), back_num, level, position after]
      def fetch_name_with_level(start_code, p)
        src = p
        back_num = 0
        level = 0
        is_num = 0
        exist_level = false
        sign = 1
        pnum_head = src
        end_code = name_end_code_point(start_code)
        name_end = @end
        r = 0
        c = 0

        raise Error.new(Err::EMPTY_GROUP_NAME) if pend?(p)

        c = code_at(p)
        p = pinc(p)
        raise Error.new(Err::EMPTY_GROUP_NAME) if c == end_code

        if digit?(c)
          is_num = 1
        elsif c == 0x2d
          is_num = 2
          sign = -1
          pnum_head = p
        elsif !code_name?(c)
          r = Err::INVALID_CHAR_IN_GROUP_NAME
        end

        until pend?(p)
          name_end = p
          c = code_at(p)
          p = pinc(p)
          if c == end_code || c == 0x29 || c == 0x2b || c == 0x2d
            r = Err::INVALID_GROUP_NAME if is_num == 2
            break
          end

          if is_num != 0
            if digit?(c)
              is_num = 1
            else
              r = Err::INVALID_GROUP_NAME
              is_num = 0
            end
          elsif !code_name?(c)
            r = Err::INVALID_CHAR_IN_GROUP_NAME
          end
        end

        if r == 0 && c != end_code
          ok = false
          if c == 0x2b || c == 0x2d
            flag = c == 0x2d ? -1 : 1
            if pend?(p)
              r = Err::INVALID_CHAR_IN_GROUP_NAME
            else
              c = code_at(p)
              q = pinc(p)
              if digit?(c)
                lv, p = scan_unsigned_number(p)
                raise Error.new(Err::TOO_BIG_NUMBER) if lv < 0

                level = lv * flag
                exist_level = true
                unless pend?(p)
                  c = code_at(p)
                  p = pinc(p)
                  ok = true if c == end_code
                end
              else
                p = q
              end
            end
          end
          unless ok || r != 0
            r = Err::INVALID_GROUP_NAME
            name_end = @end
          end
        end

        if r == 0
          if is_num != 0
            back_num, = scan_unsigned_number_to(pnum_head, name_end)
            raise Error.new(Err::TOO_BIG_NUMBER) if back_num < 0
            raise Error.new(Err::INVALID_GROUP_NAME, @pat.byteslice(src, @end - src), @enc) if back_num == 0

            back_num *= sign
          end
          return [exist_level ? 1 : 0, @pat.byteslice(src, name_end - src), back_num, level, p]
        end

        raise Error.new(r, @pat.byteslice(src, name_end - src), @enc)
      end

      # onig_scan_unsigned_number bounded by `name_end` (the C passes
      # name_end as the end).
      def scan_unsigned_number_to(p, name_end)
        saved = @end
        @end = name_end
        scan_unsigned_number(p)
      ensure
        @end = saved
      end

      # fetch_name: [name (bytes), back_num, position after]. `ref` is
      # true when a number can be used in place of the name.
      def fetch_name(start_code, p, ref)
        src = p
        back_num = 0
        end_code = name_end_code_point(start_code)
        name_end = @end
        pnum_head = src
        r = 0
        is_num = 0
        sign = 1
        c = 0

        raise Error.new(Err::EMPTY_GROUP_NAME) if pend?(p)

        c = code_at(p)
        p = pinc(p)
        raise Error.new(Err::EMPTY_GROUP_NAME) if c == end_code

        if digit?(c)
          if ref
            is_num = 1
          else
            r = Err::INVALID_GROUP_NAME
            is_num = 0
          end
        elsif c == 0x2d
          if ref
            is_num = 2
            sign = -1
            pnum_head = p
          else
            r = Err::INVALID_GROUP_NAME
            is_num = 0
          end
        elsif !code_name?(c)
          r = Err::INVALID_CHAR_IN_GROUP_NAME
        end

        if r == 0
          teardown = false
          until pend?(p)
            name_end = p
            c = code_at(p)
            p = pinc(p)
            if c == end_code || c == 0x29
              if is_num == 2
                r = Err::INVALID_GROUP_NAME
                teardown = true
              end
              break
            end

            if is_num != 0
              if digit?(c)
                is_num = 1
              else
                r = @enc.code_ctype?(c, CType::WORD) ? Err::INVALID_GROUP_NAME : Err::INVALID_CHAR_IN_GROUP_NAME
                teardown = true
                break
              end
            elsif !code_name?(c)
              r = Err::INVALID_CHAR_IN_GROUP_NAME
              teardown = true
              break
            end
          end

          unless teardown
            if c != end_code
              raise Error.new(Err::INVALID_GROUP_NAME, @pat.byteslice(src, @end - src), @enc)
            end

            if is_num != 0
              back_num, = scan_unsigned_number_to(pnum_head, name_end)
              raise Error.new(Err::TOO_BIG_NUMBER) if back_num < 0
              raise Error.new(Err::INVALID_GROUP_NAME, @pat.byteslice(src, name_end - src), @enc) if back_num == 0

              back_num *= sign
            end
            return [@pat.byteslice(src, name_end - src), back_num, p]
          end
        end

        # teardown: read on to the closer so the error shows the whole name
        until pend?(p)
          name_end = p
          c = code_at(p)
          p = pinc(p)
          break if c == end_code || c == 0x29
        end
        name_end = @end if pend?(p)
        raise Error.new(r, @pat.byteslice(src, name_end - src), @enc)
      end

      # find_str_position: where the codes `s` occur in from...to, and
      # the position after them; nil when nowhere.
      def find_str_position(s, from, to)
        p = from
        while p < to
          x = @enc.mbc_to_code(@pat, p, to)
          q = p + @enc.enclen(@pat, p, to)
          if x == s[0]
            i = 1
            while i < s.size && q < to
              x = @enc.mbc_to_code(@pat, q, to)
              break if x != s[i]

              q += @enc.enclen(@pat, q, to)
              i += 1
            end
            return [p, q] if i >= s.size
          end
          p = q
        end
        nil
      end

      # str_exist_check_with_esc
      def str_exist_check_with_esc(s, from, to, bad)
        in_esc = false
        p = from
        while p < to
          if in_esc
            in_esc = false
            p += @enc.enclen(@pat, p, to)
          else
            x = @enc.mbc_to_code(@pat, p, to)
            q = p + @enc.enclen(@pat, p, to)
            if x == s[0]
              i = 1
              while i < s.size && q < to
                x = @enc.mbc_to_code(@pat, q, to)
                break if x != s[i]

                q += @enc.enclen(@pat, q, to)
                i += 1
              end
              return true if i >= s.size

              p += @enc.enclen(@pat, p, to)
            else
              x = @enc.mbc_to_code(@pat, p, to)
              return false if x == bad

              in_esc = true if x == Syntax::ESC
              p = q
            end
          end
        end
        false
      end

      def set_char_type(tok, ctype, not_)
        tok.type = Token::CHAR_TYPE
        tok.prop_ctype = ctype
        tok.prop_not = not_
      end

      # fetch_token_in_cc: the next token inside [...]; the position after.
      def fetch_token_in_cc(tok, p)
        if pend?(p)
          tok.type = Token::EOT
          return p
        end

        c = code_at(p)
        prev_p = p
        p = pinc(p)
        tok.type = Token::CHAR
        tok.base = 0
        tok.c = c
        tok.escaped = false

        if c == 0x5d
          tok.type = Token::CC_CLOSE
        elsif c == 0x2d
          tok.type = Token::CC_RANGE
        elsif c == Syntax::ESC
          return p unless Syntax.bv?(Syntax::BACKSLASH_ESCAPE_IN_CC)
          raise Error.new(Err::END_PATTERN_AT_ESCAPE) if pend?(p)

          c = code_at(p)
          prev_p = p
          p = pinc(p)
          tok.escaped = true
          tok.c = c
          case c
          when 0x77 then set_char_type(tok, CType::WORD, false)   # w
          when 0x57 then set_char_type(tok, CType::WORD, true)    # W
          when 0x64 then set_char_type(tok, CType::DIGIT, false)  # d
          when 0x44 then set_char_type(tok, CType::DIGIT, true)   # D
          when 0x73 then set_char_type(tok, CType::SPACE, false)  # s
          when 0x53 then set_char_type(tok, CType::SPACE, true)   # S
          when 0x68 then set_char_type(tok, CType::XDIGIT, false) if Syntax.op2?(Syntax::OP2_ESC_H_XDIGIT) # h
          when 0x48 then set_char_type(tok, CType::XDIGIT, true) if Syntax.op2?(Syntax::OP2_ESC_H_XDIGIT)  # H
          when 0x70, 0x50 # p P
            unless pend?(p)
              c2 = ppeek(p)
              if c2 == 0x7b && Syntax.op2?(Syntax::OP2_ESC_P_BRACE_CHAR_PROPERTY)
                p = pinc(p)
                tok.type = Token::CHAR_PROPERTY
                tok.prop_not = c == 0x50
                if !pend?(p) && Syntax.op2?(Syntax::OP2_ESC_P_BRACE_CIRCUMFLEX_NOT)
                  c2 = code_at(p)
                  q = pinc(p)
                  if c2 == 0x5e
                    tok.prop_not = !tok.prop_not
                    p = q
                  end
                end
              else
                @env.syntax_warn("invalid Unicode Property \\#{c.chr}")
              end
            end
          when 0x78 # x
            unless pend?(p)
              prev = p
              if ppeek(p) == 0x7b && Syntax.op?(Syntax::OP_ESC_X_BRACE_HEX8)
                p = pinc(p)
                num, p = scan_unsigned_hexadecimal_number(p, 0, 8)
                raise Error.new(Err::TOO_BIG_WIDE_CHAR_VALUE) if num < 0
                raise Error.new(Err::TOO_LONG_WIDE_CHAR_VALUE) if !pend?(p) && xdigit?(ppeek(p))

                if p > prev + @enc.enclen(@pat, prev, @end) && !pend?(p) && ppeek(p) == 0x7d
                  p = pinc(p)
                  tok.type = Token::CODE_POINT
                  tok.base = 16
                  tok.code = num
                else
                  # can't read nothing or invalid format
                  p = prev
                end
              elsif Syntax.op?(Syntax::OP_ESC_X_HEX2)
                num, p = scan_unsigned_hexadecimal_number(p, 0, 2)
                raise Error.new(Err::TOO_BIG_NUMBER) if num < 0

                num = 0 if p == prev # can't read nothing, but it's not error
                tok.type = Token::RAW_BYTE
                tok.base = 16
                tok.c = num
              end
            end
          when 0x75 # u
            if !pend?(p) && Syntax.op2?(Syntax::OP2_ESC_U_HEX4)
              prev = p
              num, p = scan_unsigned_hexadecimal_number(p, 4, 4)
              raise Error.new(Err::TOO_SHORT_DIGITS) if num < -1
              raise Error.new(Err::TOO_BIG_NUMBER) if num < 0

              num = 0 if p == prev
              tok.type = Token::CODE_POINT
              tok.base = 16
              tok.code = num
            end
          when 0x6f # o
            unless pend?(p)
              prev = p
              if ppeek(p) == 0x7b && Syntax.op?(Syntax::OP_ESC_O_BRACE_OCTAL)
                p = pinc(p)
                num, p = scan_unsigned_octal_number(p, 11)
                raise Error.new(Err::TOO_BIG_WIDE_CHAR_VALUE) if num < 0

                unless pend?(p)
                  c2 = ppeek(p)
                  raise Error.new(Err::TOO_LONG_WIDE_CHAR_VALUE) if digit?(c2) && c2 < 0x38
                end

                if p > prev + @enc.enclen(@pat, prev, @end) && !pend?(p) && ppeek(p) == 0x7d
                  p = pinc(p)
                  tok.type = Token::CODE_POINT
                  tok.base = 8
                  tok.code = num
                else
                  p = prev
                end
              end
            end
          when 0x30..0x37 # 0-7
            if Syntax.op?(Syntax::OP_ESC_OCTAL3)
              p = prev_p
              prev = p
              num, p = scan_unsigned_octal_number(p, 3)
              raise Error.new(Err::TOO_BIG_NUMBER) if num < 0 || num > 0xff

              num = 0 if p == prev
              tok.type = Token::RAW_BYTE
              tok.base = 8
              tok.c = num
            end
          else
            p = prev_p
            c2, p = fetch_escaped_value(p)
            if tok.c != c2
              tok.code = c2
              tok.type = Token::CODE_POINT
            end
          end
        elsif c == 0x5b # [
          if Syntax.op?(Syntax::OP_POSIX_BRACKET) && ppeek(p) == 0x3a
            tok.backp = p # point at '[' is read
            p = pinc(p)
            if str_exist_check_with_esc([0x3a, 0x5d], p, @end, 0x5d)
              tok.type = Token::POSIX_BRACKET_OPEN
            else
              p = prev_of(p, 0x3a)
              p = cc_in_cc(tok, p)
            end
          else
            p = cc_in_cc(tok, p)
          end
        elsif c == 0x26 # &
          if Syntax.op2?(Syntax::OP2_CCLASS_SET_OP) && !pend?(p) && ppeek(p) == 0x26
            p = pinc(p)
            tok.type = Token::CC_AND
          end
        end
        p
      end

      # the `cc_in_cc:` label of fetch_token_in_cc
      def cc_in_cc(tok, p)
        if Syntax.op2?(Syntax::OP2_CCLASS_SET_OP)
          tok.type = Token::CC_CC_OPEN
        else
          @env.cc_esc_warn("[")
        end
        p
      end

      # fetch_named_backref_token: \k<...> after the opener `c`.
      def fetch_named_backref_token(c, tok, p)
        prev = p
        exist_level, name, back_num, level, p = fetch_name_with_level(c, p)
        tok.backref_exist_level = exist_level == 1
        tok.backref_level = level

        if back_num != 0
          if back_num < 0
            back_num = backref_rel_to_abs(back_num)
            raise Error.new(Err::INVALID_BACKREF) if back_num <= 0
          end

          if Syntax.bv?(Syntax::STRICT_CHECK_BACKREF)
            raise Error.new(Err::INVALID_BACKREF) if back_num > @env.num_mem || @env.mem_nodes[back_num].nil?
          end
          tok.type = Token::BACKREF
          tok.backref_by_name = false
          tok.backref_num = 1
          tok.backref_ref1 = back_num
        else
          backs = @env.reg.name_to_group_numbers(name)
          if backs.nil? || backs.empty?
            raise Error.new(Err::UNDEFINED_NAME_REFERENCE, @pat.byteslice(prev, name.bytesize), @enc)
          end
          if Syntax.bv?(Syntax::STRICT_CHECK_BACKREF)
            backs.each do |b|
              raise Error.new(Err::INVALID_BACKREF) if b > @env.num_mem || @env.mem_nodes[b].nil?
            end
          end

          tok.type = Token::BACKREF
          tok.backref_by_name = true
          if backs.size == 1 || Syntax.bv?(Syntax::USE_LEFT_MOST_NAMED_GROUP)
            tok.backref_num = 1
            tok.backref_ref1 = backs[0]
          else
            tok.backref_num = backs.size
            tok.backref_refs = backs
          end
        end
        p
      end

      # BACKREF_REL_TO_ABS
      def backref_rel_to_abs(rel_no) = @env.num_mem + 1 + rel_no

      # fetch_token: the next token outside a class; the position after.
      def fetch_token(tok, p)
        loop do
          if pend?(p)
            tok.type = Token::EOT
            return p
          end

          tok.type = Token::STRING
          tok.base = 0
          tok.backp = p

          c = code_at(p)
          p = pinc(p)
          if c == Syntax::ESC && !Syntax.op2?(Syntax::OP2_INEFFECTIVE_ESCAPE)
            raise Error.new(Err::END_PATTERN_AT_ESCAPE) if pend?(p)

            tok.backp = p
            c = code_at(p)
            prev_p = p
            p = pinc(p)
            tok.c = c
            tok.escaped = true
            p = fetch_escaped_token(tok, c, p, prev_p)
            return p
          end

          tok.c = c
          tok.escaped = false
          again, p = fetch_plain_token(tok, c, p)
          return p unless again
        end
      end

      # the `greedy_check:` label: a lazy `?`, a possessive `+`, or greedy.
      def greedy_check(tok, p)
        if !pend?(p) && ppeek(p) == 0x3f && Syntax.op?(Syntax::OP_QMARK_NON_GREEDY)
          p = pinc(p)
          tok.repeat_greedy = false
          tok.repeat_possessive = false
          p
        else
          possessive_check(tok, p)
        end
      end

      def possessive_check(tok, p)
        if !pend?(p) && ppeek(p) == 0x2b &&
           ((Syntax.op2?(Syntax::OP2_PLUS_POSSESSIVE_REPEAT) && tok.type != Token::INTERVAL) ||
            (Syntax.op2?(Syntax::OP2_PLUS_POSSESSIVE_INTERVAL) && tok.type == Token::INTERVAL))
          p = pinc(p)
          tok.repeat_greedy = true
          tok.repeat_possessive = true
        else
          tok.repeat_greedy = true
          tok.repeat_possessive = false
        end
        p
      end

      def repeat_token(tok, lower, upper, p)
        tok.type = Token::OP_REPEAT
        tok.repeat_lower = lower
        tok.repeat_upper = upper
        greedy_check(tok, p)
      end

      # `{`: an interval, or a plain brace.
      def interval_token(tok, p)
        r, p = fetch_range_quantifier(p, tok)
        return greedy_check(tok, p) if r == 0
        if r == 2 # {n}
          return possessive_check(tok, p) if Syntax.bv?(Syntax::FIXED_INTERVAL_IS_GREEDY_ONLY)

          return greedy_check(tok, p)
        end
        p # r == 1 : normal char
      end

      def anchor_token(tok, subtype, ascii_range = false)
        tok.type = Token::ANCHOR
        tok.anchor_subtype = subtype
        tok.anchor_ascii_range = ascii_range
      end

      # fetch_token's escaped branch: `c` follows the backslash, `p` follows `c`.
      def fetch_escaped_token(tok, c, p, prev_p)
        case c
        when 0x2a # *
          return repeat_token(tok, 0, REPEAT_INFINITE, p) if Syntax.op?(Syntax::OP_ESC_ASTERISK_ZERO_INF)
        when 0x2b # +
          return repeat_token(tok, 1, REPEAT_INFINITE, p) if Syntax.op?(Syntax::OP_ESC_PLUS_ONE_INF)
        when 0x3f # ?
          return repeat_token(tok, 0, 1, p) if Syntax.op?(Syntax::OP_ESC_QMARK_ZERO_ONE)
        when 0x7b # {
          return interval_token(tok, p) if Syntax.op?(Syntax::OP_ESC_BRACE_INTERVAL)
        when 0x7c # |
          tok.type = Token::ALT if Syntax.op?(Syntax::OP_ESC_VBAR_ALT)
        when 0x28 # (
          tok.type = Token::SUBEXP_OPEN if Syntax.op?(Syntax::OP_ESC_LPAREN_SUBEXP)
        when 0x29 # )
          tok.type = Token::SUBEXP_CLOSE if Syntax.op?(Syntax::OP_ESC_LPAREN_SUBEXP)
        when 0x77 then set_char_type(tok, CType::WORD, false) if Syntax.op?(Syntax::OP_ESC_W_WORD) # w
        when 0x57 then set_char_type(tok, CType::WORD, true) if Syntax.op?(Syntax::OP_ESC_W_WORD)  # W
        when 0x62 # b
          anchor_token(tok, Anchor::WORD_BOUND, @env.ascii_range? && !@env.word_bound_all_range?) if Syntax.op?(Syntax::OP_ESC_B_WORD_BOUND)
        when 0x42 # B
          anchor_token(tok, Anchor::NOT_WORD_BOUND, @env.ascii_range? && !@env.word_bound_all_range?) if Syntax.op?(Syntax::OP_ESC_B_WORD_BOUND)
        when 0x3c # <
          anchor_token(tok, Anchor::WORD_BEGIN, @env.ascii_range?) if Syntax.op?(Syntax::OP_ESC_LTGT_WORD_BEGIN_END)
        when 0x3e # >
          anchor_token(tok, Anchor::WORD_END, @env.ascii_range?) if Syntax.op?(Syntax::OP_ESC_LTGT_WORD_BEGIN_END)
        when 0x73 then set_char_type(tok, CType::SPACE, false) if Syntax.op?(Syntax::OP_ESC_S_WHITE_SPACE) # s
        when 0x53 then set_char_type(tok, CType::SPACE, true) if Syntax.op?(Syntax::OP_ESC_S_WHITE_SPACE)  # S
        when 0x64 then set_char_type(tok, CType::DIGIT, false) if Syntax.op?(Syntax::OP_ESC_D_DIGIT)       # d
        when 0x44 then set_char_type(tok, CType::DIGIT, true) if Syntax.op?(Syntax::OP_ESC_D_DIGIT)        # D
        when 0x68 then set_char_type(tok, CType::XDIGIT, false) if Syntax.op2?(Syntax::OP2_ESC_H_XDIGIT)   # h
        when 0x48 then set_char_type(tok, CType::XDIGIT, true) if Syntax.op2?(Syntax::OP2_ESC_H_XDIGIT)    # H
        when 0x41 then anchor_token(tok, Anchor::BEGIN_BUF) if Syntax.op?(Syntax::OP_ESC_AZ_BUF_ANCHOR)    # A
        when 0x5a then anchor_token(tok, Anchor::SEMI_END_BUF) if Syntax.op?(Syntax::OP_ESC_AZ_BUF_ANCHOR) # Z
        when 0x7a then anchor_token(tok, Anchor::END_BUF) if Syntax.op?(Syntax::OP_ESC_AZ_BUF_ANCHOR)      # z
        when 0x47 then anchor_token(tok, Anchor::BEGIN_POSITION) if Syntax.op?(Syntax::OP_ESC_CAPITAL_G_BEGIN_ANCHOR) # G
        when 0x60 then anchor_token(tok, Anchor::BEGIN_BUF) if Syntax.op2?(Syntax::OP2_ESC_GNU_BUF_ANCHOR) # `
        when 0x27 then anchor_token(tok, Anchor::END_BUF) if Syntax.op2?(Syntax::OP2_ESC_GNU_BUF_ANCHOR)   # '
        when 0x78 # x
          return p if pend?(p)

          prev = p
          if ppeek(p) == 0x7b && Syntax.op?(Syntax::OP_ESC_X_BRACE_HEX8)
            p = pinc(p)
            num, p = scan_unsigned_hexadecimal_number(p, 0, 8)
            raise Error.new(Err::TOO_BIG_WIDE_CHAR_VALUE) if num < 0
            raise Error.new(Err::TOO_LONG_WIDE_CHAR_VALUE) if !pend?(p) && xdigit?(ppeek(p))

            if p > prev + @enc.enclen(@pat, prev, @end) && !pend?(p) && ppeek(p) == 0x7d
              p = pinc(p)
              tok.type = Token::CODE_POINT
              tok.code = num
            else
              p = prev
            end
          elsif Syntax.op?(Syntax::OP_ESC_X_HEX2)
            num, p = scan_unsigned_hexadecimal_number(p, 0, 2)
            raise Error.new(Err::TOO_BIG_NUMBER) if num < 0

            num = 0 if p == prev
            tok.type = Token::RAW_BYTE
            tok.base = 16
            tok.c = num
          end
        when 0x75 # u
          return p if pend?(p)

          if Syntax.op2?(Syntax::OP2_ESC_U_HEX4)
            prev = p
            num, p = scan_unsigned_hexadecimal_number(p, 4, 4)
            raise Error.new(Err::TOO_SHORT_DIGITS) if num < -1
            raise Error.new(Err::TOO_BIG_NUMBER) if num < 0

            num = 0 if p == prev
            tok.type = Token::CODE_POINT
            tok.base = 16
            tok.code = num
          end
        when 0x6f # o
          return p if pend?(p)

          prev = p
          if ppeek(p) == 0x7b && Syntax.op?(Syntax::OP_ESC_O_BRACE_OCTAL)
            p = pinc(p)
            num, p = scan_unsigned_octal_number(p, 11)
            raise Error.new(Err::TOO_BIG_WIDE_CHAR_VALUE) if num < 0

            unless pend?(p)
              c2 = ppeek(p)
              raise Error.new(Err::TOO_LONG_WIDE_CHAR_VALUE) if digit?(c2) && c2 < 0x38
            end

            if p > prev + @enc.enclen(@pat, prev, @end) && !pend?(p) && ppeek(p) == 0x7d
              p = pinc(p)
              tok.type = Token::CODE_POINT
              tok.code = num
            else
              p = prev
            end
          end
        when 0x31..0x39 # 1-9
          p = prev_p
          prev = p
          num, p = scan_unsigned_number(p)
          if num >= 0 && num <= MAX_BACKREF_NUM &&
             Syntax.op?(Syntax::OP_DECIMAL_BACKREF) && (num <= @env.num_mem || num <= 9) # This spec. from GNU regex
            if Syntax.bv?(Syntax::STRICT_CHECK_BACKREF)
              raise Error.new(Err::INVALID_BACKREF) if num > @env.num_mem || @env.mem_nodes[num].nil?
            end

            tok.type = Token::BACKREF
            tok.backref_num = 1
            tok.backref_ref1 = num
            tok.backref_by_name = false
            tok.backref_exist_level = false
            return p
          end

          # skip_backref:
          if c == 0x38 || c == 0x39
            # normal char
            p = prev
            return pinc(p)
          end

          p = prev
          return octal_token(tok, c, p)
        when 0x30 # 0
          return octal_token(tok, c, p)
        when 0x6b # k
          if !pend?(p) && Syntax.op2?(Syntax::OP2_ESC_K_NAMED_BACKREF)
            c = code_at(p)
            q = pinc(p)
            if c == 0x3c || c == 0x27
              p = fetch_named_backref_token(c, tok, q)
            else
              @env.syntax_warn("invalid back reference")
            end
          end
        when 0x67 # g
          if !pend?(p) && Syntax.op2?(Syntax::OP2_ESC_G_BRACE_BACKREF)
            c = code_at(p)
            q = pinc(p)
            p = fetch_named_backref_token(c, tok, q) if c == 0x7b
          end
          if !pend?(p) && Syntax.op2?(Syntax::OP2_ESC_G_SUBEXP_CALL)
            c = code_at(p)
            q = pinc(p)
            if c == 0x3c || c == 0x27
              p = q
              gnum = -1
              rel = false
              name = nil
              cnext = ppeek(p)
              if cnext == 0x30
                p = pinc(p)
                if ppeek(p) == name_end_code_point(c) # \g<0>, \g'0'
                  p = pinc(p)
                  name = "".b
                  gnum = 0
                end
              elsif cnext == 0x2b
                p = pinc(p)
                rel = true
              end
              prev = p
              if gnum < 0
                name, gnum, p = fetch_name(c, p, true)
              end

              tok.type = Token::CALL
              tok.call_name = name
              tok.call_gnum = gnum
              tok.call_rel = rel
            else
              @env.syntax_warn("invalid subexp call")
            end
          end
        when 0x51 # Q
          tok.type = Token::QUOTE_OPEN if Syntax.op2?(Syntax::OP2_ESC_CAPITAL_Q_QUOTE)
        when 0x70, 0x50 # p P
          if ppeek(p) == 0x7b && Syntax.op2?(Syntax::OP2_ESC_P_BRACE_CHAR_PROPERTY)
            p = pinc(p)
            tok.type = Token::CHAR_PROPERTY
            tok.prop_not = c == 0x50

            if !pend?(p) && Syntax.op2?(Syntax::OP2_ESC_P_BRACE_CIRCUMFLEX_NOT)
              c2 = code_at(p)
              q = pinc(p)
              if c2 == 0x5e
                tok.prop_not = !tok.prop_not
                p = q
              end
            end
          else
            @env.syntax_warn("invalid Unicode Property \\#{c.chr}")
          end
        when 0x52 # R
          tok.type = Token::LINEBREAK if Syntax.op2?(Syntax::OP2_ESC_CAPITAL_R_LINEBREAK)
        when 0x58 # X
          tok.type = Token::EXTENDED_GRAPHEME_CLUSTER if Syntax.op2?(Syntax::OP2_ESC_CAPITAL_X_EXTENDED_GRAPHEME_CLUSTER)
        when 0x4b # K
          tok.type = Token::KEEP if Syntax.op2?(Syntax::OP2_ESC_CAPITAL_K_KEEP)
        else
          p = prev_p
          c2, p = fetch_escaped_value(p)
          if tok.c != c2
            tok.type = Token::CODE_POINT
            tok.code = c2
          else # string
            p = tok.backp + @enc.enclen(@pat, tok.backp, @end)
          end
        end
        p
      end

      # The `case '0':` arm shared with a failed backref: \0oo or \ooo.
      def octal_token(tok, c, p)
        if Syntax.op?(Syntax::OP_ESC_OCTAL3)
          prev = p
          num, p = scan_unsigned_octal_number(p, c == 0x30 ? 2 : 3)
          raise Error.new(Err::TOO_BIG_NUMBER) if num < 0 || num > 0xff

          num = 0 if p == prev
          tok.type = Token::RAW_BYTE
          tok.base = 8
          tok.c = num
        elsif c != 0x30
          p = pinc(p)
        end
        p
      end

      # fetch_token's plain branch: [start over?, position].
      def fetch_plain_token(tok, c, p)
        case c
        when 0x2e # .
          tok.type = Token::ANYCHAR if Syntax.op?(Syntax::OP_DOT_ANYCHAR)
        when 0x2a # *
          return [false, repeat_token(tok, 0, REPEAT_INFINITE, p)] if Syntax.op?(Syntax::OP_ASTERISK_ZERO_INF)
        when 0x2b # +
          return [false, repeat_token(tok, 1, REPEAT_INFINITE, p)] if Syntax.op?(Syntax::OP_PLUS_ONE_INF)
        when 0x3f # ?
          return [false, repeat_token(tok, 0, 1, p)] if Syntax.op?(Syntax::OP_QMARK_ZERO_ONE)
        when 0x7b # {
          return [false, interval_token(tok, p)] if Syntax.op?(Syntax::OP_BRACE_INTERVAL)
        when 0x7c # |
          tok.type = Token::ALT if Syntax.op?(Syntax::OP_VBAR_ALT)
        when 0x28 # (
          if ppeek(p) == 0x3f && Syntax.op2?(Syntax::OP2_QMARK_GROUP_EFFECT)
            p = pinc(p)
            if ppeek(p) == 0x23 # (?#...)
              p = pinc(p)
              loop do
                raise Error.new(Err::END_PATTERN_IN_GROUP) if pend?(p)

                c = code_at(p)
                p = pinc(p)
                if c == Syntax::ESC
                  p = pinc(p) unless pend?(p)
                elsif c == 0x29
                  break
                end
              end
              return [true, p]
            end
            # (?&name), (?n), (?R), (?0), (?+n), (?-n)
            c = ppeek(p)
            if (c == 0x26 || c == 0x52 || digit?(c)) && Syntax.op2?(Syntax::OP2_QMARK_SUBEXP_CALL)
              if c == 0x52 || c == 0x30
                p = pinc(p) # skip 'R' / '0'
                unless ppeek(p) == 0x29
                  raise Error.new(Err::INVALID_GROUP_NAME, @pat.byteslice(p - 1, 2), @enc)
                end
                p = pinc(p) # skip ')'
                name = "".b
                gnum = 0
              else
                numref = true
                if c == 0x26 # (?&name)
                  p = pinc(p)
                  numref = false # don't allow number name
                end
                name, gnum, p = fetch_name(0x28, p, numref)
              end
              tok.type = Token::CALL
              tok.call_name = name
              tok.call_gnum = gnum
              tok.call_rel = false
              return [false, p]
            elsif (c == 0x2d || c == 0x2b) && Syntax.op2?(Syntax::OP2_QMARK_SUBEXP_CALL)
              # (?+n), (?-n)
              q = pinc(p) # skip '-' / '+'
              cnext = ppeek(q)
              if digit?(cnext)
                q = p if c == 0x2d # PUNFETCH
                name, gnum, p = fetch_name(0x28, q, true)
                tok.type = Token::CALL
                tok.call_name = name
                tok.call_gnum = gnum
                tok.call_rel = true
                return [false, p]
              end
            end
            if ppeek(p) == 0x50 && Syntax.op2?(Syntax::OP2_QMARK_CAPITAL_P_NAMED_GROUP)
              q = pinc(p) # skip 'P'
              raise Error.new(Err::UNDEFINED_GROUP_OPTION) if pend?(q)

              c = code_at(q)
              q = pinc(q)
              if c == 0x3d # (?P=name): backref
                return [false, fetch_named_backref_token(0x28, tok, q)]
              elsif c == 0x3e # (?P>name): subexp call
                name, gnum, q = fetch_name(0x28, q, false)
                tok.type = Token::CALL
                tok.call_name = name
                tok.call_gnum = gnum
                tok.call_rel = false
                return [false, q]
              end
            end
            p = prev_of(p, 0x3f) # PUNFETCH
          end
          tok.type = Token::SUBEXP_OPEN if Syntax.op?(Syntax::OP_LPAREN_SUBEXP)
        when 0x29 # )
          tok.type = Token::SUBEXP_CLOSE if Syntax.op?(Syntax::OP_LPAREN_SUBEXP)
        when 0x5e # ^
          anchor_token(tok, @env.singleline? ? Anchor::BEGIN_BUF : Anchor::BEGIN_LINE) if Syntax.op?(Syntax::OP_LINE_ANCHOR)
        when 0x24 # $
          anchor_token(tok, @env.singleline? ? Anchor::SEMI_END_BUF : Anchor::END_LINE) if Syntax.op?(Syntax::OP_LINE_ANCHOR)
        when 0x5b # [
          tok.type = Token::CC_OPEN if Syntax.op?(Syntax::OP_BRACKET_CC)
        when 0x5d # ]
          @env.close_bracket_without_esc_warn("]") if tok.backp > 0 # /].../ is allowed.
        when 0x23 # #
          if @env.extend?
            until pend?(p)
              c = code_at(p)
              p = pinc(p)
              break if @enc.code_ctype?(c, CType::NEWLINE)
            end
            return [true, p]
          end
        when 0x20, 0x09, 0x0a, 0x0d, 0x0c
          return [true, p] if @env.extend?
        end
        [false, p]
      end
    end
  end
end
