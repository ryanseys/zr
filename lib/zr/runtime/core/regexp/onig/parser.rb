# frozen_string_literal: true

# Derived from Onigmo (BSD-2-Clause); see THIRD_PARTY_NOTICES.md.
#
# Onigmo's parser: a pattern's tokens to its tree (regparse.c:
# 2100-2450 and 4200-6853). A port under the BSD-2-Clause license
# reproduced in regexp.rb.
class Regexp
  module Onig
    class Parser
      include Lexer

      # ?:0, *:1, +:2, ??:3, *?:4, +?:5
      POPULAR_Q_STR = %w[? * + ?? *? +?].freeze
      REDUCE_Q_STR = ["", "", "*", "*?", "??", "+ and ??", "+? and ?"].freeze

      RQ_ASIS = 0  # as is
      RQ_DEL = 1   # delete parent
      RQ_A = 2     # to '*'
      RQ_AQ = 3    # to '*?'
      RQ_QQ = 4    # to '??'
      RQ_P_QQ = 5  # to '+)??'

      # ReduceTypeTable[child][parent]
      REDUCE_TYPE_TABLE = [
        [RQ_DEL, RQ_A, RQ_A, RQ_QQ, RQ_AQ, RQ_ASIS],   # '?'
        [RQ_DEL, RQ_DEL, RQ_DEL, RQ_P_QQ, RQ_P_QQ, RQ_DEL], # '*'
        [RQ_A, RQ_A, RQ_DEL, RQ_ASIS, RQ_P_QQ, RQ_DEL], # '+'
        [RQ_DEL, RQ_AQ, RQ_AQ, RQ_DEL, RQ_AQ, RQ_AQ],   # '??'
        [RQ_DEL, RQ_DEL, RQ_DEL, RQ_DEL, RQ_DEL, RQ_DEL], # '*?'
        [RQ_ASIS, RQ_ASIS, RQ_ASIS, RQ_AQ, RQ_AQ, RQ_DEL], # '+?'
      ].freeze

      CCS_VALUE = 0
      CCS_RANGE = 1
      CCS_COMPLETE = 2
      CCS_START = 3

      CCV_SB = 0
      CCV_CODE_POINT = 1
      CCV_CLASS = 2

      attr_reader :env

      def initialize(reg, pattern, warnings)
        @reg = reg
        @pat = pattern.b
        @end = @pat.bytesize
        @env = ScanEnv.new(reg, @pat, warnings)
        @enc = reg.enc
        @p = 0
      end

      # onig_parse_make_tree: the tree, with reg.num_mem set.
      def parse_make_tree
        @reg.names_clear
        @p = 0
        root = parse_regexp
        @reg.num_mem = @env.num_mem
        root
      end

      # ---- quantifiers ----

      def self.popular_quantifier_num(q)
        if q.greedy
          if q.lower == 0
            return 0 if q.upper == 1
            return 1 if q.upper == REPEAT_INFINITE
          elsif q.lower == 1
            return 2 if q.upper == REPEAT_INFINITE
          end
        elsif q.lower == 0
          return 3 if q.upper == 1
          return 4 if q.upper == REPEAT_INFINITE
        elsif q.lower == 1
          return 5 if q.upper == REPEAT_INFINITE
        end
        -1
      end

      # onig_reduce_nested_quantifier
      def self.reduce_nested_quantifier(pnode, cnode)
        pnum = popular_quantifier_num(pnode)
        cnum = popular_quantifier_num(cnode)
        return if pnum < 0 || cnum < 0

        case REDUCE_TYPE_TABLE[cnum][pnum]
        when RQ_DEL
          pnode.copy_from!(cnode)
        when RQ_A
          pnode.target = cnode.target
          pnode.lower = 0
          pnode.upper = REPEAT_INFINITE
          pnode.greedy = true
        when RQ_AQ
          pnode.target = cnode.target
          pnode.lower = 0
          pnode.upper = REPEAT_INFINITE
          pnode.greedy = false
        when RQ_QQ
          pnode.target = cnode.target
          pnode.lower = 0
          pnode.upper = 1
          pnode.greedy = false
        when RQ_P_QQ
          pnode.target = cnode
          pnode.lower = 0
          pnode.upper = 1
          pnode.greedy = false
          cnode.lower = 1
          cnode.upper = REPEAT_INFINITE
          cnode.greedy = true
        when RQ_ASIS
          pnode.target = cnode
        end
      end

      # set_quantifier: 0 when `target` is taken, 1 when the quantifier
      # is {1,1} and dropped, 2 when the target's last character was
      # split off as the target.
      def set_quantifier(qn, target, group)
        return 1 if qn.lower == 1 && qn.upper == 1

        case target.ntype
        when Node::STR
          if !group && target.str_can_be_split?(@enc)
            n = target.str_split_last_char(@enc)
            unless n.nil?
              qn.target = n
              return 2
            end
          end
        when Node::QTFR
          # check redundant double repeat.
          # verbose warn (?:.?)? etc... but not warn (.?)? etc...
          nestq_num = Parser.popular_quantifier_num(qn)
          targetq_num = Parser.popular_quantifier_num(target)

          if nestq_num >= 0 && targetq_num >= 0 && Syntax.bv?(Syntax::WARN_REDUNDANT_NESTED_REPEAT)
            case REDUCE_TYPE_TABLE[targetq_num][nestq_num]
            when RQ_ASIS
              nil
            when RQ_DEL
              @env.syntax_warn("regular expression has redundant nested repeat operator '#{POPULAR_Q_STR[targetq_num]}'")
            else
              @env.syntax_warn("nested repeat operator '#{POPULAR_Q_STR[targetq_num]}' and '#{POPULAR_Q_STR[nestq_num]}' was replaced with '#{REDUCE_Q_STR[REDUCE_TYPE_TABLE[targetq_num][nestq_num]]}' in regular expression")
            end
          end

          if targetq_num >= 0
            if nestq_num >= 0
              Parser.reduce_nested_quantifier(qn, target)
              return 0
            elsif targetq_num == 1 || targetq_num == 2 # * or +
              # (?:a*){n,m}, (?:a+){n,m} => (?:a*){n,n}, (?:a+){n,n}
              if qn.upper != REPEAT_INFINITE && qn.upper > 1 && qn.greedy
                qn.upper = qn.lower == 0 ? 1 : qn.lower
              end
            end
          end
        end

        qn.target = target
        0
      end

      # ---- character classes ----

      # BITSET_SET_BIT_CHKDUP
      def bs_set_chkdup(cc, pos)
        @env.cc_dup_warn(pos, pos) if BitSet.at?(cc.bs, pos)
        cc.bs = BitSet.set(cc.bs, pos)
      end

      def bitset_set_range(cc, from, to)
        i = from
        while i <= to && i < 256
          bs_set_chkdup(cc, i)
          i += 1
        end
      end

      # add_ctype_to_cc_by_range
      def add_ctype_to_cc_by_range(cc, not_, sb_out, mbr)
        n = mbr.size / 2
        if !not_
          i = 0
          sb_done = false
          while i < n && !sb_done
            j = mbr[i * 2]
            while j <= mbr[i * 2 + 1]
              if j >= sb_out
                if j > mbr[i * 2]
                  cc.mbuf = CodeRange.add_to_buf(cc.mbuf, @env, j, mbr[i * 2 + 1])
                  i += 1
                end
                sb_done = true
                break
              end
              bs_set_chkdup(cc, j)
              j += 1
            end
            i += 1 unless sb_done
          end

          while i < n
            cc.mbuf = CodeRange.add_to_buf(cc.mbuf, @env, mbr[i * 2], mbr[i * 2 + 1])
            i += 1
          end
        else
          prev = 0
          sb_done = false
          n.times do |i|
            j = prev
            while j < mbr[i * 2]
              if j >= sb_out
                sb_done = true
                break
              end
              bs_set_chkdup(cc, j)
              j += 1
            end
            break if sb_done

            prev = mbr[i * 2 + 1] + 1
          end
          unless sb_done
            j = prev
            while j < sb_out
              bs_set_chkdup(cc, j)
              j += 1
            end
          end

          prev = sb_out
          n.times do |i|
            cc.mbuf = CodeRange.add_to_buf(cc.mbuf, @env, prev, mbr[i * 2] - 1) if prev < mbr[i * 2]
            prev = mbr[i * 2 + 1] + 1
          end
          cc.mbuf = CodeRange.add_to_buf(cc.mbuf, @env, prev, 0x7fffffff) if prev < 0x7fffffff
        end
      end

      # ADD_ALL_MULTI_BYTE_RANGE
      def add_all_multi_byte_range(cc)
        cc.mbuf = CodeRange.set_all_multi_byte(@enc, cc.mbuf, @env) unless @enc.singlebyte?
      end

      # add_ctype_to_cc
      def add_ctype_to_cc(cc, ctype, not_, ascii_range)
        range = @enc.ctype_code_range(ctype)
        unless range.nil?
          sb_out, ranges = range
          if ascii_range
            ccwork = Node.cclass
            add_ctype_to_cc_by_range(ccwork, not_, sb_out, ranges)
            if not_
              ccwork.mbuf = CodeRange.add_to_buf0(ccwork.mbuf, @env, 0x80, LAST_CODE_POINT, false)
            else
              ccascii = Node.cclass
              if @enc.min_len > 1
                ccascii.mbuf = CodeRange.add(ccascii.mbuf, @env, 0x00, 0x7f)
              else
                bitset_set_range(ccascii, 0x00, 0x7f)
              end
              CClassOps.and(ccwork, ccascii, @env)
            end
            CClassOps.or(cc, ccwork, @env)
          else
            add_ctype_to_cc_by_range(cc, not_, sb_out, ranges)
          end
          return
        end

        maxcode = ascii_range ? 0x80 : 256
        case ctype
        when CType::ALPHA, CType::BLANK, CType::CNTRL, CType::DIGIT, CType::LOWER, CType::PUNCT,
             CType::SPACE, CType::UPPER, CType::XDIGIT, CType::ASCII, CType::ALNUM
          if not_
            256.times { |c| bs_set_chkdup(cc, c) unless @enc.code_ctype?(c, ctype) }
            add_all_multi_byte_range(cc)
          else
            256.times { |c| bs_set_chkdup(cc, c) if @enc.code_ctype?(c, ctype) }
          end
        when CType::GRAPH, CType::PRINT
          if not_
            256.times { |c| bs_set_chkdup(cc, c) if !@enc.code_ctype?(c, ctype) || c >= maxcode }
            add_all_multi_byte_range(cc) if ascii_range
          else
            maxcode.times { |c| bs_set_chkdup(cc, c) if @enc.code_ctype?(c, ctype) }
            add_all_multi_byte_range(cc) unless ascii_range
          end
        when CType::WORD
          if !not_
            maxcode.times { |c| bs_set_chkdup(cc, c) if @enc.code_ctype?(c, CType::WORD) }
            add_all_multi_byte_range(cc) unless ascii_range
          else
            256.times do |c|
              # check invalid code point
              bs_set_chkdup(cc, c) if @enc.code_to_mbclen(c) > 0 && (!@enc.code_ctype?(c, CType::WORD) || c >= maxcode)
            end
            add_all_multi_byte_range(cc) if ascii_range
          end
        else
          raise Error.new(Err::PARSER_BUG)
        end
      end

      POSIX_BRACKETS = {
        "alnum" => CType::ALNUM, "alpha" => CType::ALPHA, "blank" => CType::BLANK,
        "cntrl" => CType::CNTRL, "digit" => CType::DIGIT, "graph" => CType::GRAPH,
        "lower" => CType::LOWER, "print" => CType::PRINT, "punct" => CType::PUNCT,
        "space" => CType::SPACE, "upper" => CType::UPPER, "xdigit" => CType::XDIGIT,
        "ascii" => CType::ASCII, "word" => CType::WORD,
      }.freeze
      POSIX_BRACKET_CHECK_LIMIT_LENGTH = 20
      POSIX_BRACKET_NAME_MIN_LEN = 4

      # parse_posix_bracket: [0, p] when a bracket was read into cc,
      # [1, p] when it is not one after all.
      def parse_posix_bracket(cc, asc_cc, p)
        if ppeek(p) == 0x5e
          p = pinc(p)
          not_ = true
        else
          not_ = false
        end

        if @enc.strlen(@pat, p, @end) >= POSIX_BRACKET_NAME_MIN_LEN + 3
          ascii_range = @env.ascii_range? && !@env.posix_bracket_all_range?
          POSIX_BRACKETS.each do |name, ctype|
            next unless @enc.with_ascii_strncmp(@pat, p, @end, name, name.bytesize) == 0

            p = @enc.step(@pat, p, @end, name.bytesize)
            raise Error.new(Err::INVALID_POSIX_BRACKET_TYPE) if @enc.with_ascii_strncmp(@pat, p, @end, ":]", 2) != 0

            add_ctype_to_cc(cc, ctype, not_, ascii_range)
            if !asc_cc.nil? && ctype != CType::WORD && ctype != CType::ASCII && !ascii_range
              add_ctype_to_cc(asc_cc, ctype, not_, ascii_range)
            end
            p = pinc(pinc(p))
            return [0, p]
          end
        end

        # not_posix_bracket:
        c = 0
        i = 0
        while !pend?(p) && (c = ppeek(p)) != 0x3a && c != 0x5d
          p = pinc(p)
          i += 1
          break if i > POSIX_BRACKET_CHECK_LIMIT_LENGTH
        end
        if c == 0x3a && !pend?(p)
          p = pinc(p)
          unless pend?(p)
            c = code_at(p)
            p = pinc(p)
            raise Error.new(Err::INVALID_POSIX_BRACKET_TYPE) if c == 0x5d
          end
        end
        [1, p] # 1: is not POSIX bracket, but no error.
      end

      # fetch_char_property_to_ctype: [ctype, p] for the name up to `}`.
      def fetch_char_property_to_ctype(p)
        src = p
        r = Err::INVALID_CHAR_PROPERTY_NAME
        start = prev = p
        until pend?(p)
          prev = p
          c = code_at(p)
          p = pinc(p)
          if c == 0x7d
            r = @enc.property_name_to_ctype(@pat, start, prev)
            break if r < 0

            return [r, p]
          elsif c == 0x28 || c == 0x29 || c == 0x7b || c == 0x7c
            break
          end
        end
        raise Error.new(r, @pat.byteslice(src, prev - src), @enc)
      end

      # parse_char_property: \p{...} as a class node.
      def parse_char_property(tok)
        ctype, @p = fetch_char_property_to_ctype(@p)
        node = Node.cclass
        add_ctype_to_cc(node, ctype, false, false)
        node.cclass_set_not if tok.prop_not

        if @env.ignorecase? && ctype != CType::ASCII
          node = cclass_case_fold(node, node, node)
        end
        node
      end

      # next_state_class: [vs, val_type, state]
      def next_state_class(cc, asc_cc, vs, type, state)
        raise Error.new(Err::CHAR_CLASS_VALUE_AT_END_OF_RANGE) if state == CCS_RANGE

        if state == CCS_VALUE && type != CCV_CLASS
          if type == CCV_SB
            bs_set_chkdup(cc, vs)
            asc_cc.bs = BitSet.set(asc_cc.bs, vs) unless asc_cc.nil?
          elsif type == CCV_CODE_POINT
            cc.mbuf = CodeRange.add(cc.mbuf, @env, vs, vs)
            asc_cc.mbuf = CodeRange.add0(asc_cc.mbuf, @env, vs, vs, false) unless asc_cc.nil?
          end
        end
        [vs, CCV_CLASS, CCS_VALUE]
      end

      # next_state_val: [from, from_israw, type, state] after `to` came in.
      def next_state_val(cc, asc_cc, from, to, from_israw, to_israw, intype, type, state)
        case state
        when CCS_VALUE
          if type == CCV_SB
            bs_set_chkdup(cc, from)
            asc_cc.bs = BitSet.set(asc_cc.bs, from) unless asc_cc.nil?
          elsif type == CCV_CODE_POINT
            cc.mbuf = CodeRange.add(cc.mbuf, @env, from, from)
            asc_cc.mbuf = CodeRange.add0(asc_cc.mbuf, @env, from, from, false) unless asc_cc.nil?
          end
        when CCS_RANGE
          if intype == type
            if intype == CCV_SB
              raise Error.new(Err::INVALID_CODE_POINT_VALUE) if from > 0xff || to > 0xff

              if from > to
                raise Error.new(Err::EMPTY_RANGE_IN_CHAR_CLASS) unless Syntax.bv?(Syntax::ALLOW_EMPTY_RANGE_IN_CC)
              else
                bitset_set_range(cc, from, to)
                bitset_set_range(asc_cc, from, to) unless asc_cc.nil?
              end
            else
              cc.mbuf = CodeRange.add(cc.mbuf, @env, from, to)
              asc_cc.mbuf = CodeRange.add0(asc_cc.mbuf, @env, from, to, false) unless asc_cc.nil?
            end
          elsif from > to
            raise Error.new(Err::EMPTY_RANGE_IN_CHAR_CLASS) unless Syntax.bv?(Syntax::ALLOW_EMPTY_RANGE_IN_CC)
          else
            bitset_set_range(cc, from, to < 0xff ? to : 0xff)
            cc.mbuf = CodeRange.add(cc.mbuf, @env, from, to)
            unless asc_cc.nil?
              bitset_set_range(asc_cc, from, to < 0xff ? to : 0xff)
              asc_cc.mbuf = CodeRange.add0(asc_cc.mbuf, @env, from, to, false)
            end
          end
          state = CCS_COMPLETE
          return [to, to_israw, intype, state]
        when CCS_COMPLETE, CCS_START
          state = CCS_VALUE
        end
        [to, to_israw, intype, state]
      end

      # code_exist_check
      def code_exist_check(c, from, ignore_escaped)
        in_esc = false
        p = from
        until pend?(p)
          if ignore_escaped && in_esc
            in_esc = false
            p = pinc(p)
          else
            code = code_at(p)
            p = pinc(p)
            return true if code == c

            in_esc = true if code == Syntax::ESC
          end
        end
        false
      end

      # parse_char_class: [node, asc_node] for [...] starting after the '['.
      def parse_char_class(tok)
        @env.parse_depth += 1
        raise Error.new(Err::PARSE_DEPTH_LIMIT_OVER) if @env.parse_depth > PARSE_DEPTH_LIMIT

        prev_cc = asc_prev_cc = nil
        @p = fetch_token_in_cc(tok, @p)
        r = tok.type
        if r == Token::CHAR && tok.c == 0x5e && !tok.escaped
          neg = true
          @p = fetch_token_in_cc(tok, @p)
          r = tok.type
        else
          neg = false
        end

        if r == Token::CC_CLOSE
          raise Error.new(Err::EMPTY_CHAR_CLASS) unless code_exist_check(0x5d, @p, true)

          @env.cc_esc_warn("]")
          r = tok.type = Token::CHAR # allow []...]
        end

        node = Node.cclass
        cc = node
        if @env.ignorecase?
          asc_node = Node.cclass
          asc_cc = asc_node
        else
          asc_node = nil
          asc_cc = nil
        end

        and_start = false
        state = CCS_START
        vs = 0
        val_type = CCV_SB
        val_israw = false

        while r != Token::CC_CLOSE
          fetched = false
          v = nil
          in_israw = false
          in_type = nil
          entry = nil # :val_entry (length from v), :val_entry2 (in_type set), :next_class, nil

          case r
          when Token::CHAR
            len = 0
            if tok.code >= 256 || (len = @enc.code_to_mbclen(tok.c)) > 1
              in_type = CCV_CODE_POINT
            elsif len < 0
              raise Error.new(len)
            else
              in_type = CCV_SB
            end
            v = tok.c
            in_israw = false
            entry = :val_entry2
          when Token::RAW_BYTE
            # tok->base != 0 : octal or hexadec.
            if !@enc.singlebyte? && tok.base != 0
              buf = [tok.c]
              psave = @p
              base = tok.base
              i = 1
              while i < @enc.max_len
                @p = fetch_token_in_cc(tok, @p)
                r = tok.type
                if r != Token::RAW_BYTE || tok.base != base
                  fetched = true
                  break
                end
                buf << tok.c
                i += 1
              end

              raise Error.new(Err::TOO_SHORT_MULTI_BYTE_STRING) if i < @enc.min_len

              bytes = buf.pack("C*")
              len = @enc.enclen(bytes, 0, i)
              if i < len
                raise Error.new(Err::TOO_SHORT_MULTI_BYTE_STRING)
              elsif i > len # fetch back
                @p = psave
                (len - 1).times { @p = fetch_token_in_cc(tok, @p) }
                fetched = false
                i = len
              end

              if i == 1
                v = buf[0]
                in_type = CCV_SB
              else
                v = @enc.mbc_to_code(bytes, 0, bytes.bytesize)
                in_type = CCV_CODE_POINT
              end
            else
              v = tok.c
              in_type = CCV_SB
            end
            in_israw = true
            entry = :val_entry2
          when Token::CODE_POINT
            v = tok.code
            in_israw = true
            entry = :val_entry
          when Token::POSIX_BRACKET_OPEN
            pr, p2 = parse_posix_bracket(cc, asc_cc, @p)
            if pr == 1 # is not POSIX bracket
              @env.cc_esc_warn("[")
              @p = tok.backp
              v = tok.c
              in_israw = false
              entry = :val_entry
            else
              @p = p2
              entry = :next_class
            end
          when Token::CHAR_TYPE
            add_ctype_to_cc(cc, tok.prop_ctype, tok.prop_not, @env.ascii_range?)
            if !asc_cc.nil? && tok.prop_ctype != CType::WORD
              add_ctype_to_cc(asc_cc, tok.prop_ctype, tok.prop_not, @env.ascii_range?)
            end
            entry = :next_class
          when Token::CHAR_PROPERTY
            ctype, @p = fetch_char_property_to_ctype(@p)
            add_ctype_to_cc(cc, ctype, tok.prop_not, false)
            if !asc_cc.nil? && ctype != CType::ASCII
              add_ctype_to_cc(asc_cc, ctype, tok.prop_not, false)
            end
            entry = :next_class
          when Token::CC_RANGE
            if state == CCS_VALUE
              @p = fetch_token_in_cc(tok, @p)
              r = tok.type
              fetched = true
              if r == Token::CC_CLOSE # allow [x-]
                v = 0x2d
                in_israw = false
                entry = :val_entry
              elsif r == Token::CC_AND
                @env.cc_esc_warn("-")
                v = 0x2d
                in_israw = false
                entry = :val_entry
              else
                raise Error.new(Err::UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS) if val_type == CCV_CLASS

                state = CCS_RANGE
              end
            elsif state == CCS_START
              # [-xa] is allowed
              v = tok.c
              in_israw = false
              @p = fetch_token_in_cc(tok, @p)
              r = tok.type
              fetched = true
              # [--x] or [a&&-x] is warned.
              @env.cc_esc_warn("-") if r == Token::CC_RANGE || and_start
              entry = :val_entry
            elsif state == CCS_RANGE
              @env.cc_esc_warn("-")
              in_type = CCV_SB # [!--x] is allowed
              v = tok.c
              in_israw = false
              entry = :val_entry2
            else # CCS_COMPLETE
              @p = fetch_token_in_cc(tok, @p)
              r = tok.type
              fetched = true
              if r == Token::CC_CLOSE # allow [a-b-]
                v = 0x2d
                in_israw = false
                entry = :val_entry
              elsif r == Token::CC_AND
                @env.cc_esc_warn("-")
                v = 0x2d
                in_israw = false
                entry = :val_entry
              elsif Syntax.bv?(Syntax::ALLOW_DOUBLE_RANGE_OP_IN_CC)
                @env.cc_esc_warn("-")
                v = 0x2d
                in_israw = false
                entry = :val_entry # [0-9-a] is allowed as [0-9\-a]
              else
                raise Error.new(Err::UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS)
              end
            end
          when Token::CC_CC_OPEN # [
            anode, aasc_node = parse_char_class(tok)
            CClassOps.or(cc, anode, @env)
            CClassOps.or(asc_cc, aasc_node, @env) unless aasc_node.nil?
          when Token::CC_AND # &&
            if state == CCS_VALUE
              vs, val_israw, val_type, state = next_state_val(cc, asc_cc, vs, 0, val_israw, false, val_type, val_type, state)
            end
            # initialize local variables
            and_start = true
            state = CCS_START

            if !prev_cc.nil?
              CClassOps.and(prev_cc, cc, @env)
              CClassOps.and(asc_prev_cc, asc_cc, @env) unless asc_cc.nil?
            else
              prev_cc = cc
              cc = Node.cclass
              unless asc_cc.nil?
                asc_prev_cc = asc_cc
                asc_cc = Node.cclass
              end
            end
            cc.flags = 0
            cc.bs = 0
            cc.mbuf = nil
            unless asc_cc.nil?
              asc_cc.flags = 0
              asc_cc.bs = 0
              asc_cc.mbuf = nil
            end
          when Token::EOT
            raise Error.new(Err::PREMATURE_END_OF_CHAR_CLASS)
          else
            raise Error.new(Err::PARSER_BUG)
          end

          case entry
          when :val_entry
            len = @enc.code_to_mbclen(v)
            raise Error.new(len) if len < 0

            in_type = len == 1 ? CCV_SB : CCV_CODE_POINT
            vs, val_israw, val_type, state = next_state_val(cc, asc_cc, vs, v, val_israw, in_israw, in_type, val_type, state)
          when :val_entry2
            vs, val_israw, val_type, state = next_state_val(cc, asc_cc, vs, v, val_israw, in_israw, in_type, val_type, state)
          when :next_class
            vs, val_type, state = next_state_class(cc, asc_cc, vs, val_type, state)
          end

          if fetched
            r = tok.type
          else
            @p = fetch_token_in_cc(tok, @p)
            r = tok.type
          end
        end

        if state == CCS_VALUE
          next_state_val(cc, asc_cc, vs, 0, val_israw, false, val_type, val_type, state)
        end

        unless prev_cc.nil?
          CClassOps.and(prev_cc, cc, @env)
          cc = prev_cc
          unless asc_cc.nil?
            CClassOps.and(asc_prev_cc, asc_cc, @env)
            asc_cc = asc_prev_cc
          end
        end

        if neg
          cc.cclass_set_not
          asc_cc&.cclass_set_not
        else
          cc.cclass_clear_not
          asc_cc&.cclass_clear_not
        end
        if cc.cclass_not? && Syntax.bv?(Syntax::NOT_NEWLINE_IN_NEGATIVE_CC)
          is_empty = cc.mbuf.nil? && BitSet.empty?(cc.bs)
          if !is_empty && @enc.code_ctype?(0x0a, CType::NEWLINE)
            if @enc.code_to_mbclen(0x0a) == 1
              bs_set_chkdup(cc, 0x0a)
            else
              cc.mbuf = CodeRange.add(cc.mbuf, @env, 0x0a, 0x0a)
            end
          end
        end
        @env.parse_depth -= 1
        [node, asc_node]
      end

      # is_singlebyte_range
      def singlebyte_range?(code)
        return true if @enc.max_len == 1
        return false if @enc.min_len > 1

        code < 0x80
      end

      # cclass_case_fold: `np` (whose class is `cc`) with every case fold
      # added; an alternation with the multi-character folds when there
      # are any.
      def cclass_case_fold(np, cc, asc_cc)
        alt_root = nil
        tail = nil
        @enc.apply_all_case_fold(@env.case_fold_flag) do |from, to|
          add_flag = if asc_cc.nil?
                       false
                     elsif (from < 128) == (to[0] < 128)
                       true
                     else
                       in_asc = CodeRange.code_in_cc?(@enc, from, asc_cc)
                       asc_cc.cclass_not? ? !in_asc : in_asc
                     end

          if to.size == 1
            is_in = CodeRange.code_in_cc?(@enc, from, cc)
            if (is_in && !cc.cclass_not?) || (!is_in && cc.cclass_not?)
              if add_flag
                if singlebyte_range?(to[0])
                  cc.bs = BitSet.set(cc.bs, to[0])
                else
                  cc.mbuf = CodeRange.add0(cc.mbuf, @env, to[0], to[0], false)
                end
              end
            end
          elsif CodeRange.code_in_cc?(@enc, from, cc) && !cc.cclass_not?
            snode = Node.str(to.map { |c| @enc.code_to_mbc(c) }.join)
            # char-class expanded multi-char only compare with string folded at match time.
            snode.flag |= StrFlag::AMBIG
            cell = Node.alt(snode, nil)
            if tail.nil?
              alt_root = cell
            else
              tail.cdr = cell
            end
            tail = cell
          end
        end
        alt_root.nil? ? np : Node.alt(np, alt_root)
      end

      # node_linebreak: (?>\x0D\x0A|[\x0A-\x0D\x{85}\x{2028}\x{2029}])
      def node_linebreak
        left = Node.str_raw(@enc.code_to_mbc(0x0d) + @enc.code_to_mbc(0x0a))
        right = Node.cclass
        if @enc.min_len > 1
          right.mbuf = CodeRange.add(right.mbuf, @env, 0x0a, 0x0d)
        else
          bitset_set_range(right, 0x0a, 0x0d)
        end
        if @enc.unicode?
          right.mbuf = CodeRange.add(right.mbuf, @env, 0x85, 0x85)
          right.mbuf = CodeRange.add(right.mbuf, @env, 0x2028, 0x2029)
        end
        node = Node.enclose(Enclose::STOP_BACKTRACK)
        node.target = Node.alt(left, Node.alt(right, nil))
        node
      end

      # propname2ctype: the encoding's lookup, reading the name as ASCII.
      def propname2ctype(propname)
        name = propname.b
        ctype = @enc.property_name_to_ctype(name, 0, name.bytesize, Enc::ASCII_ENC)
        raise Error.new(ctype, name, @enc) if ctype < 0

        ctype
      end

      def add_property_to_cc(cc, propname, not_) = add_ctype_to_cc(cc, propname2ctype(propname), not_, false)

      def create_property_node(propname)
        node = Node.cclass
        add_property_to_cc(node, propname, false)
        node
      end

      def quantify_node(node, lower, upper)
        tmp = Node.quantifier(lower, upper, false)
        tmp.target = node
        tmp
      end

      def quantify_property_node(propname, repetitions)
        node = create_property_node(propname)
        lower = 0
        upper = REPEAT_INFINITE
        case repetitions
        when "?" then upper = 1
        when "+" then lower = 1
        when "*" then nil
        when "2" then lower = upper = 2
        else raise Error.new(Err::PARSER_BUG)
        end
        quantify_node(node, lower, upper)
      end

      # create_node_from_array: the nodes as a right-nested list or alternation.
      def node_from_array(kind, nodes)
        nodes.reverse.inject(nil) { |tmp, n| kind == :list ? Node.list(n, tmp) : Node.alt(n, tmp) }
      end

      # node_extended_grapheme_cluster: \X
      def node_extended_grapheme_cluster
        alts = []
        # CRLF, common for both Unicode and non-Unicode
        alts << Node.str_raw(@enc.code_to_mbc(0x0d) + @enc.code_to_mbc(0x0a))

        if @enc.unicode?
          propname2ctype("Grapheme_Cluster_Break=Extend")
          # [Control CR LF]
          control = Node.cclass
          add_property_to_cc(control, "Grapheme_Cluster_Break=Control", false)
          if @enc.min_len > 1
            control.mbuf = CodeRange.add(control.mbuf, @env, 0x0a, 0x0a)
            control.mbuf = CodeRange.add(control.mbuf, @env, 0x0d, 0x0d)
          else
            control.bs = BitSet.set(control.bs, 0x0a)
            control.bs = BitSet.set(control.bs, 0x0d)
          end
          alts << control

          # precore* core postcore*
          list = []
          list << quantify_property_node("Grapheme_Cluster_Break=Prepend", "*")

          core_alts = []
          # hangul-syllable := L* (V+ | LV V* | LVT) T* | L+ | T+
          h_list = []
          h_list << quantify_property_node("Grapheme_Cluster_Break=L", "*")
          h_alt2 = []
          h_alt2 << quantify_property_node("Grapheme_Cluster_Break=V", "+")
          h_list2 = [create_property_node("Grapheme_Cluster_Break=LV"), quantify_property_node("Grapheme_Cluster_Break=V", "*")]
          h_alt2 << node_from_array(:list, h_list2)
          h_alt2 << create_property_node("Grapheme_Cluster_Break=LVT")
          h_list << node_from_array(:alt, h_alt2)
          h_list << quantify_property_node("Grapheme_Cluster_Break=T", "*")
          core_alts << node_from_array(:list, h_list)
          core_alts << quantify_property_node("Grapheme_Cluster_Break=L", "+")
          core_alts << quantify_property_node("Grapheme_Cluster_Break=T", "+")

          # ri-sequence := RI RI
          core_alts << quantify_property_node("Regional_Indicator", "2")

          # xpicto-sequence := \p{Extended_Pictographic} (Extend* ZWJ \p{Extended_Pictographic})*
          xp_list = [create_property_node("Extended_Pictographic")]
          ex_list = [quantify_property_node("Grapheme_Cluster_Break=Extend", "*"),
                     Node.str_raw(@enc.code_to_mbc(0x200d)),
                     create_property_node("Extended_Pictographic")]
          xp_list << quantify_node(node_from_array(:list, ex_list), 0, REPEAT_INFINITE)
          core_alts << node_from_array(:list, xp_list)

          # conjunctCluster := \p{InCB=Consonant} ([\p{InCB=Extend} \p{InCB=Linker}]* \p{InCB=Linker} [\p{InCB=Extend} \p{InCB=Linker}]* \p{InCB=Consonant})+
          cc_list = [create_property_node("InCB=Consonant")]
          inner = []
          n = create_property_node("InCB=Extend")
          add_property_to_cc(n, "InCB=Linker", false)
          inner << quantify_node(n, 0, REPEAT_INFINITE)
          inner << create_property_node("InCB=Linker")
          n = create_property_node("InCB=Extend")
          add_property_to_cc(n, "InCB=Linker", false)
          inner << quantify_node(n, 0, REPEAT_INFINITE)
          inner << create_property_node("InCB=Consonant")
          cc_list << quantify_node(node_from_array(:list, inner), 1, REPEAT_INFINITE)
          core_alts << node_from_array(:list, cc_list)

          # [^Control CR LF]
          rest = Node.cclass
          if @enc.min_len > 1
            dup_not_warned = @env.warnings_flag | ~Syntax::WARN_CC_DUP
            @env.warnings_flag |= Syntax::WARN_CC_DUP
            add_property_to_cc(rest, "Grapheme_Cluster_Break=Control", false)
            rest.mbuf = CodeRange.add(rest.mbuf, @env, 0x0a, 0x0a)
            rest.mbuf = CodeRange.add(rest.mbuf, @env, 0x0d, 0x0d)
            rest.mbuf = CodeRange.not_buf(@enc, rest.mbuf, @env)
            @env.warnings_flag &= dup_not_warned
          else
            add_property_to_cc(rest, "Grapheme_Cluster_Break=Control", true)
            rest.bs = BitSet.clear(rest.bs, 0x0a)
            rest.bs = BitSet.clear(rest.bs, 0x0d)
          end
          core_alts << rest

          list << node_from_array(:alt, core_alts)

          # postcore*; postcore = [Extend ZWJ SpacingMark]
          post = create_property_node("Grapheme_Cluster_Break=Extend")
          add_property_to_cc(post, "Grapheme_Cluster_Break=SpacingMark", false)
          post.mbuf = CodeRange.add(post.mbuf, @env, 0x200d, 0x200d)
          list << quantify_node(post, 0, REPEAT_INFINITE)

          alts << node_from_array(:list, list)
        end

        # RubySyntax: (?m:.), to catch invalid stuff
        option = @env.option | Option::MULTILINE
        any = Node.option(option)
        any.target = Node.anychar
        alts << any

        top_alt = node_from_array(:alt, alts)
        stop = Node.enclose(Enclose::STOP_BACKTRACK)
        stop.target = top_alt

        if @enc.unicode?
          # Don't ignore case.
          node = Node.option(@env.option & ~Option::IGNORECASE)
          node.target = stop
          node
        else
          stop
        end
      end

      # is_onechar_cclass: the one code point in the class, or nil.
      def onechar_cclass(cc)
        return nil if cc.cclass_not?

        c = nil
        unless cc.mbuf.nil?
          if cc.mbuf.size == 2 && cc.mbuf[0] == cc.mbuf[1]
            c = cc.mbuf[0]
            # skip if c is included in the bitset
            c = nil if c < 256 && BitSet.at?(cc.bs, c)
          else
            return nil # the bbuf contains multiple chars
          end
        end

        bs = cc.bs
        if bs != 0
          return nil if (bs & (bs - 1)) != 0 || !c.nil? # multiple chars

          c = bs.bit_length - 1
        end
        c
      end

      # ---- the grammar ----

      # parse_enclose: [r, node] for "(" already read; r is 1 for a bare
      # group, 2 for an option-only group, 0 otherwise.
      def parse_enclose(tok, term)
        raise Error.new(Err::END_PATTERN_WITH_UNMATCHED_PARENTHESIS) if pend?(@p)

        option = @env.option
        node = nil
        if ppeek(@p) == 0x3f && Syntax.op2?(Syntax::OP2_QMARK_GROUP_EFFECT)
          @p = pinc(@p)
          raise Error.new(Err::END_PATTERN_IN_GROUP) if pend?(@p)

          c = code_at(@p)
          @p = pinc(@p)
          case c
          when 0x3a # (?:...) grouping only
            return [1, parse_group(tok, term)]
          when 0x3d then node = Node.anchor(Anchor::PREC_READ)
          when 0x21 then node = Node.anchor(Anchor::PREC_READ_NOT)
          when 0x3e then node = Node.enclose(Enclose::STOP_BACKTRACK)
          when 0x7e # (?~...) absent operator
            raise Error.new(Err::UNDEFINED_GROUP_OPTION) unless Syntax.op2?(Syntax::OP2_QMARK_TILDE_ABSENT)

            node = Node.enclose(Enclose::ABSENT)
          when 0x27 # (?'name'...)
            raise Error.new(Err::UNDEFINED_GROUP_OPTION) unless Syntax.op2?(Syntax::OP2_QMARK_LT_NAMED_GROUP)

            node = named_group(c)
          when 0x50 # (?P<name>...)
            if !pend?(@p) && Syntax.op2?(Syntax::OP2_QMARK_CAPITAL_P_NAMED_GROUP)
              c = code_at(@p)
              @p = pinc(@p)
              raise Error.new(Err::UNDEFINED_GROUP_OPTION) unless c == 0x3c

              node = named_group(c)
            else
              raise Error.new(Err::UNDEFINED_GROUP_OPTION)
            end
          when 0x3c # look behind (?<=...), (?<!...), or (?<name>...)
            raise Error.new(Err::END_PATTERN_WITH_UNMATCHED_PARENTHESIS) if pend?(@p)

            c = code_at(@p)
            @p = pinc(@p)
            if c == 0x3d
              node = Node.anchor(Anchor::LOOK_BEHIND)
            elsif c == 0x21
              node = Node.anchor(Anchor::LOOK_BEHIND_NOT)
            elsif Syntax.op2?(Syntax::OP2_QMARK_LT_NAMED_GROUP)
              @p = prev_of(@p, c)
              node = named_group(0x3c)
            else
              raise Error.new(Err::UNDEFINED_GROUP_OPTION)
            end
          when 0x28 # conditional expression: (?(cond)yes), (?(cond)yes|no)
            raise Error.new(Err::UNDEFINED_GROUP_OPTION) if pend?(@p) || !Syntax.op2?(Syntax::OP2_QMARK_LPAREN_CONDITION)

            name = nil
            c = code_at(@p)
            @p = pinc(@p)
            if digit?(c) # (n)
              @p = prev_of(@p, c)
              _, num, @p = fetch_name(0x28, @p, true)
              if Syntax.bv?(Syntax::STRICT_CHECK_BACKREF)
                raise Error.new(Err::INVALID_BACKREF) if num > @env.num_mem || @env.mem_nodes[num].nil?
              end
            elsif c == 0x3c || c == 0x27 # (<name>), ('name')
              name = @p
              @p = fetch_named_backref_token(c, tok, @p)
              raise Error.new(Err::UNDEFINED_GROUP_OPTION) unless ppeek(@p) == 0x29

              @p = pinc(@p)
              num = if Syntax.bv?(Syntax::USE_LEFT_MOST_NAMED_GROUP)
                      tok.backref_ref1
                    else
                      tok.backref_num > 1 ? tok.backref_refs[0] : tok.backref_ref1
                    end
            else
              raise Error.new(Err::INVALID_CONDITION_PATTERN)
            end
            node = Node.enclose(Enclose::CONDITION)
            node.regnum = num
            node.state |= Status::NAME_REF unless name.nil?
          when 0x5e # loads default options
            raise Error.new(Err::UNDEFINED_GROUP_OPTION) unless !pend?(@p) && Syntax.op2?(Syntax::OP2_OPTION_PERL)

            option = onoff(option, Option::ASCII_RANGE, true)
            option = onoff(option, Option::IGNORECASE, true)
            option = onoff(option, Option::SINGLELINE, false)
            option = onoff(option, Option::MULTILINE, true)
            option = onoff(option, Option::EXTEND, true)
            c = code_at(@p)
            @p = pinc(@p)
            return parse_option_group(tok, term, c, option)
          when 0x2d, 0x69, 0x6d, 0x73, 0x78, 0x61, 0x64, 0x6c, 0x75
            return parse_option_group(tok, term, c, option)
          else
            raise Error.new(Err::UNDEFINED_GROUP_OPTION)
          end
        else
          return [1, parse_group(tok, term)] if (@env.option & Option::DONT_CAPTURE_GROUP) != 0

          node = Node.enclose_memory(@env.option, false)
          node.regnum = @env.add_mem_entry
        end

        @p = fetch_token(tok, @p)
        target = parse_subexp(tok, term)

        if node.ntype == Node::ANCHOR
          node.target = target
        else
          node.target = target
          if node.type == Enclose::MEMORY
            # Don't move this to previous of parse_subexp()
            @env.set_mem_node(node.regnum, node)
          elsif node.type == Enclose::CONDITION && target.ntype != Node::ALT
            # convert (?(cond)yes) to (?(cond)yes|empty)
            node.target = Node.alt(target, Node.alt(Node.empty, nil))
          end
        end
        [0, node]
      end

      # the `group:` label: (?:...)
      def parse_group(tok, term)
        @p = fetch_token(tok, @p)
        parse_subexp(tok, term)
      end

      # the `named_group1:` label: (?<name>...) with `c` the opener.
      def named_group(c)
        name, _, @p = fetch_name(c, @p, false)
        num = @env.add_mem_entry
        @reg.name_add(name, num, @env)
        node = Node.enclose_memory(@env.option, true)
        node.regnum = num
        @env.num_named += 1
        node
      end

      # ONOFF
      def onoff(v, f, negative) = negative ? v & ~f : v | f

      # the option letters of (?imx-imx...) with `c` the first one read.
      def parse_option_group(tok, term, c, option)
        neg = false
        loop do
          case c
          when 0x3a, 0x29 then nil
          when 0x2d then neg = true
          when 0x78 then option = onoff(option, Option::EXTEND, neg)
          when 0x69 then option = onoff(option, Option::IGNORECASE, neg)
          when 0x73
            raise Error.new(Err::UNDEFINED_GROUP_OPTION) unless Syntax.op2?(Syntax::OP2_OPTION_PERL)

            option = onoff(option, Option::MULTILINE, neg)
          when 0x6d
            if Syntax.op2?(Syntax::OP2_OPTION_PERL)
              option = onoff(option, Option::SINGLELINE, !neg)
            elsif Syntax.op2?(Syntax::OP2_OPTION_RUBY)
              option = onoff(option, Option::MULTILINE, neg)
            else
              raise Error.new(Err::UNDEFINED_GROUP_OPTION)
            end
          when 0x61 # limits \d, \s, \w and POSIX brackets to ASCII range
            raise Error.new(Err::UNDEFINED_GROUP_OPTION) unless (Syntax.op2?(Syntax::OP2_OPTION_PERL) || Syntax.op2?(Syntax::OP2_OPTION_RUBY)) && !neg

            option = onoff(option, Option::ASCII_RANGE, false)
            option = onoff(option, Option::POSIX_BRACKET_ALL_RANGE, true)
            option = onoff(option, Option::WORD_BOUND_ALL_RANGE, true)
          when 0x75
            raise Error.new(Err::UNDEFINED_GROUP_OPTION) unless (Syntax.op2?(Syntax::OP2_OPTION_PERL) || Syntax.op2?(Syntax::OP2_OPTION_RUBY)) && !neg

            option = onoff(option, Option::ASCII_RANGE, true)
            option = onoff(option, Option::POSIX_BRACKET_ALL_RANGE, true)
            option = onoff(option, Option::WORD_BOUND_ALL_RANGE, true)
          when 0x64
            if Syntax.op2?(Syntax::OP2_OPTION_PERL) && !neg
              option = onoff(option, Option::ASCII_RANGE, true)
            elsif Syntax.op2?(Syntax::OP2_OPTION_RUBY) && !neg
              option = onoff(option, Option::ASCII_RANGE, false)
              option = onoff(option, Option::POSIX_BRACKET_ALL_RANGE, false)
              option = onoff(option, Option::WORD_BOUND_ALL_RANGE, false)
            else
              raise Error.new(Err::UNDEFINED_GROUP_OPTION)
            end
          when 0x6c
            raise Error.new(Err::UNDEFINED_GROUP_OPTION) unless Syntax.op2?(Syntax::OP2_OPTION_PERL) && !neg

            option = onoff(option, Option::ASCII_RANGE, true)
          else
            raise Error.new(Err::UNDEFINED_GROUP_OPTION)
          end

          if c == 0x29
            return [2, Node.option(option)] # option only
          elsif c == 0x3a
            prev = @env.option
            @env.option = option
            begin
              @p = fetch_token(tok, @p)
              target = parse_subexp(tok, term)
            ensure
              @env.option = prev
            end
            node = Node.option(option)
            node.target = target
            return [0, node]
          end

          raise Error.new(Err::END_PATTERN_IN_GROUP) if pend?(@p)

          c = code_at(@p)
          @p = pinc(@p)
        end
      end

      # parse_exp: one term with its quantifiers; tok contains the token after it.
      def parse_exp(tok, term)
        return Node.empty if tok.type == term

        parse_depth = @env.parse_depth
        group = false
        np = nil

        case tok.type
        when Token::ALT, Token::EOT
          return Node.empty
        when Token::SUBEXP_OPEN
          r, np = parse_enclose(tok, Token::SUBEXP_CLOSE)
          if r == 1
            group = true
          elsif r == 2 # option only
            prev = @env.option
            @env.option = np.option
            begin
              @p = fetch_token(tok, @p)
              target = parse_subexp(tok, term)
            ensure
              @env.option = prev
            end
            np.target = target
            return np
          end
        when Token::SUBEXP_CLOSE
          raise Error.new(Err::UNMATCHED_CLOSE_PARENTHESIS) unless Syntax.bv?(Syntax::ALLOW_UNMATCHED_CLOSE_SUBEXP)

          return tok.escaped ? parse_raw_byte(tok, term, parse_depth) : parse_string(tok, term, parse_depth)
        when Token::LINEBREAK
          np = node_linebreak
        when Token::EXTENDED_GRAPHEME_CLUSTER
          np = node_extended_grapheme_cluster
        when Token::KEEP
          np = Node.anchor(Anchor::KEEP)
        when Token::STRING
          return parse_string(tok, term, parse_depth)
        when Token::RAW_BYTE
          return parse_raw_byte(tok, term, parse_depth)
        when Token::CODE_POINT
          np = Node.empty
          np.str_cat(@enc.code_to_mbc(tok.code))
          return string_loop(np, tok, term, parse_depth)
        when Token::QUOTE_OPEN
          qstart = @p
          found = find_str_position([Syntax::ESC, 0x45], qstart, @end)
          if found.nil?
            qend = nextp = @end
          else
            qend, nextp = found
          end
          np = Node.str(@pat.byteslice(qstart, qend - qstart))
          @p = nextp
        when Token::CHAR_TYPE
          case tok.prop_ctype
          when CType::WORD
            np = Node.ctype(tok.prop_ctype, tok.prop_not, @env.ascii_range?)
          when CType::SPACE, CType::DIGIT, CType::XDIGIT
            np = Node.cclass
            add_ctype_to_cc(np, tok.prop_ctype, false, @env.ascii_range?)
            np.cclass_set_not if tok.prop_not
          else
            raise Error.new(Err::PARSER_BUG)
          end
        when Token::CHAR_PROPERTY
          np = parse_char_property(tok)
        when Token::CC_OPEN
          np, asc_node = parse_char_class(tok)
          code = onechar_cclass(np)
          unless code.nil?
            np = Node.empty
            np.str_cat(@enc.code_to_mbc(code))
            return string_loop(np, tok, term, parse_depth)
          end
          np = cclass_case_fold(np, np, asc_node) if @env.ignorecase?
        when Token::ANYCHAR
          np = Node.anychar
        when Token::ANYCHAR_ANYTIME
          qn = Node.quantifier(0, REPEAT_INFINITE, false)
          qn.target = Node.anychar
          np = qn
        when Token::BACKREF
          refs = tok.backref_num > 1 ? tok.backref_refs : [tok.backref_ref1]
          np = Node.backref(refs, tok.backref_by_name, tok.backref_exist_level, tok.backref_level, @env)
        when Token::CALL
          gnum = tok.call_gnum
          if gnum < 0 || tok.call_rel
            gnum -= 1 if gnum > 0
            gnum = backref_rel_to_abs(gnum)
            raise Error.new(Err::INVALID_BACKREF) if gnum <= 0
          end
          np = Node.call(tok.call_name, gnum)
          @env.num_call += 1
        when Token::ANCHOR
          np = Node.anchor(tok.anchor_subtype)
          np.ascii_range = tok.anchor_ascii_range
        when Token::OP_REPEAT, Token::INTERVAL
          if Syntax.bv?(Syntax::CONTEXT_INDEP_REPEAT_OPS)
            raise Error.new(Err::TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED) if Syntax.bv?(Syntax::CONTEXT_INVALID_REPEAT_OPS)

            np = Node.empty
          else
            return parse_string(tok, term, parse_depth)
          end
        else
          raise Error.new(Err::PARSER_BUG)
        end

        @p = fetch_token(tok, @p)
        parse_repeat(np, tok, group, parse_depth)
      end

      # the `tk_byte:` label: a run of literal characters.
      def parse_string(tok, term, parse_depth)
        np = Node.str(@pat.byteslice(tok.backp, @p - tok.backp))
        string_loop(np, tok, term, parse_depth)
      end

      # the `string_loop:` label: more literal characters onto `np`.
      def string_loop(np, tok, _term, parse_depth)
        loop do
          @p = fetch_token(tok, @p)
          if tok.type == Token::STRING
            np.str_cat(@pat.byteslice(tok.backp, @p - tok.backp))
          elsif tok.type == Token::CODE_POINT
            np.str_cat(@enc.code_to_mbc(tok.code))
          else
            break
          end
        end
        parse_repeat(np, tok, false, parse_depth)
      end

      # the `tk_raw_byte:` label: \xHH bytes assembled into one character.
      def parse_raw_byte(tok, term, parse_depth)
        np = Node.str_raw_char(tok.c)
        len = 1
        loop do
          if len >= @enc.min_len && len == @enc.enclen(np.s, 0, np.s.bytesize)
            @p = fetch_token(tok, @p)
            np.flag &= ~StrFlag::RAW
            return parse_repeat(np, tok, false, parse_depth)
          end

          @p = fetch_token(tok, @p)
          raise Error.new(Err::TOO_SHORT_MULTI_BYTE_STRING) if tok.type != Token::RAW_BYTE

          np.str_cat(tok.c.chr)
          len += 1
        end
      end

      # the `repeat:` loop: the quantifiers after a term. The target's
      # slot moves into the list a split creates, as the C's targetp does.
      def parse_repeat(np, tok, group, parse_depth)
        holder = nil # nil: np itself; a LIST cell: its car
        loop do
          r = tok.type
          return np unless r == Token::OP_REPEAT || r == Token::INTERVAL

          target = holder.nil? ? np : holder.car
          parse_depth += 1
          raise Error.new(Err::PARSE_DEPTH_LIMIT_OVER) if parse_depth > PARSE_DEPTH_LIMIT

          qn = Node.quantifier(tok.repeat_lower, tok.repeat_upper, r == Token::INTERVAL)
          qn.greedy = tok.repeat_greedy
          r = set_quantifier(qn, target, group)

          if tok.repeat_possessive
            en = Node.enclose(Enclose::STOP_BACKTRACK)
            en.target = qn
            qn = en
          end

          if r == 0
            if holder.nil? then np = qn else holder.car = qn end
          elsif r == 2 # split case: /abc+/
            cell = Node.list(target, nil)
            tmp = Node.list(qn, nil)
            cell.cdr = tmp
            if holder.nil? then np = cell else holder.car = cell end
            holder = tmp
          end
          @p = fetch_token(tok, @p)
        end
      end

      # parse_branch: the terms up to |, ) or the end, as a list.
      def parse_branch(tok, term)
        node = parse_exp(tok, term)
        r = tok.type
        return node if r == Token::EOT || r == term || r == Token::ALT

        top = Node.list(node, nil)
        tail = top
        while r != Token::EOT && r != term && r != Token::ALT
          node = parse_exp(tok, term)
          r = tok.type
          if node.ntype == Node::LIST
            tail.cdr = node
            node = node.cdr until node.cdr.nil?
            tail = node
          else
            tail.cdr = Node.list(node, nil)
            tail = tail.cdr
          end
        end
        top
      end

      # parse_subexp: alternatives up to `term` (EOT or SUBEXP_CLOSE).
      def parse_subexp(tok, term)
        @env.parse_depth += 1
        raise Error.new(Err::PARSE_DEPTH_LIMIT_OVER) if @env.parse_depth > PARSE_DEPTH_LIMIT

        node = parse_branch(tok, term)
        r = tok.type
        if r == term
          top = node
        elsif r == Token::ALT
          top = Node.alt(node, nil)
          tail = top
          while r == Token::ALT
            @p = fetch_token(tok, @p)
            node = parse_branch(tok, term)
            r = tok.type
            tail.cdr = Node.alt(node, nil)
            tail = tail.cdr
          end
          raise Error.new(term == Token::SUBEXP_CLOSE ? Err::END_PATTERN_WITH_UNMATCHED_PARENTHESIS : Err::PARSER_BUG) if tok.type != term
        else
          raise Error.new(term == Token::SUBEXP_CLOSE ? Err::END_PATTERN_WITH_UNMATCHED_PARENTHESIS : Err::PARSER_BUG)
        end
        @env.parse_depth -= 1
        top
      end

      # parse_regexp
      def parse_regexp
        tok = Token.new
        @p = fetch_token(tok, @p)
        top = parse_subexp(tok, Token::EOT)

        if @env.num_call > 0
          # Capture the pattern itself. It is used for (?R), (?0) and \g<0>.
          np = Node.enclose_memory(@env.option, false)
          np.regnum = 0
          np.target = top
          @env.set_mem_node(0, np)
          top = np
        end
        top
      end
    end
  end
end
