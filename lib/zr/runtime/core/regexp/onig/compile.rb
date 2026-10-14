# frozen_string_literal: true

# Onigmo's compiler: a tuned tree to its byte code (regcomp.c:386-1894).
# The bytes are laid out as Onigmo lays them out, little-endian: an
# opcode is one byte, a relative or absolute address, a length and a
# repeat number are four, a memory number is two, an option word is
# four, a bit set is thirty-two. A port under the BSD-2-Clause license
# reproduced in regexp.rb.
class Regexp
  module Onig
    # enum OpCode (regint.h)
    module Op
      FINISH = 0
      END_ = 1
      EXACT1 = 2
      EXACT2 = 3
      EXACT3 = 4
      EXACT4 = 5
      EXACT5 = 6
      EXACTN = 7
      EXACTMB2N1 = 8
      EXACTMB2N2 = 9
      EXACTMB2N3 = 10
      EXACTMB2N = 11
      EXACTMB3N = 12
      EXACTMBN = 13
      EXACT1_IC = 14
      EXACTN_IC = 15
      CCLASS = 16
      CCLASS_MB = 17
      CCLASS_MIX = 18
      CCLASS_NOT = 19
      CCLASS_MB_NOT = 20
      CCLASS_MIX_NOT = 21
      ANYCHAR = 22
      ANYCHAR_ML = 23
      ANYCHAR_STAR = 24
      ANYCHAR_ML_STAR = 25
      ANYCHAR_STAR_PEEK_NEXT = 26
      ANYCHAR_ML_STAR_PEEK_NEXT = 27
      WORD = 28
      NOT_WORD = 29
      WORD_BOUND = 30
      NOT_WORD_BOUND = 31
      WORD_BEGIN = 32
      WORD_END = 33
      ASCII_WORD = 34
      NOT_ASCII_WORD = 35
      ASCII_WORD_BOUND = 36
      NOT_ASCII_WORD_BOUND = 37
      ASCII_WORD_BEGIN = 38
      ASCII_WORD_END = 39
      BEGIN_BUF = 40
      END_BUF = 41
      BEGIN_LINE = 42
      END_LINE = 43
      SEMI_END_BUF = 44
      BEGIN_POSITION = 45
      BACKREF1 = 46
      BACKREF2 = 47
      BACKREFN = 48
      BACKREFN_IC = 49
      BACKREF_MULTI = 50
      BACKREF_MULTI_IC = 51
      BACKREF_WITH_LEVEL = 52
      MEMORY_START = 53
      MEMORY_START_PUSH = 54
      MEMORY_END_PUSH = 55
      MEMORY_END_PUSH_REC = 56
      MEMORY_END = 57
      MEMORY_END_REC = 58
      KEEP = 59
      FAIL = 60
      JUMP = 61
      PUSH = 62
      POP = 63
      PUSH_OR_JUMP_EXACT1 = 64
      PUSH_IF_PEEK_NEXT = 65
      REPEAT = 66
      REPEAT_NG = 67
      REPEAT_INC = 68
      REPEAT_INC_NG = 69
      REPEAT_INC_SG = 70
      REPEAT_INC_NG_SG = 71
      NULL_CHECK_START = 72
      NULL_CHECK_END = 73
      NULL_CHECK_END_MEMST = 74
      NULL_CHECK_END_MEMST_PUSH = 75
      PUSH_POS = 76
      POP_POS = 77
      PUSH_POS_NOT = 78
      FAIL_POS = 79
      PUSH_STOP_BT = 80
      POP_STOP_BT = 81
      LOOK_BEHIND = 82
      PUSH_LOOK_BEHIND_NOT = 83
      FAIL_LOOK_BEHIND_NOT = 84
      PUSH_ABSENT_POS = 85
      ABSENT = 86
      ABSENT_END = 87
      CALL = 88
      RETURN = 89
      CONDITION = 90
      STATE_CHECK_PUSH = 91
      STATE_CHECK_PUSH_OR_JUMP = 92
      STATE_CHECK = 93
      STATE_CHECK_ANYCHAR_STAR = 94
      STATE_CHECK_ANYCHAR_ML_STAR = 95
      SET_OPTION_PUSH = 96
      SET_OPTION = 97

      NAMES = constants.reject { |c| c == :NAMES }.sort_by { |c| const_get(c) }.map { |c| c.to_s.delete_suffix("_") }.freeze

      SIZE_OPCODE = 1
      SIZE_RELADDR = 4
      SIZE_ABSADDR = 4
      SIZE_LENGTH = 4
      SIZE_MEMNUM = 2
      SIZE_REPEATNUM = 4
      SIZE_OPTION = 4
      SIZE_CODE_POINT = 4
      SIZE_BITSET = 32

      SIZE_OP_ANYCHAR_STAR = SIZE_OPCODE
      SIZE_OP_ANYCHAR_STAR_PEEK_NEXT = SIZE_OPCODE + 1
      SIZE_OP_JUMP = SIZE_OPCODE + SIZE_RELADDR
      SIZE_OP_PUSH = SIZE_OPCODE + SIZE_RELADDR
      SIZE_OP_POP = SIZE_OPCODE
      SIZE_OP_PUSH_OR_JUMP_EXACT1 = SIZE_OPCODE + SIZE_RELADDR + 1
      SIZE_OP_PUSH_IF_PEEK_NEXT = SIZE_OPCODE + SIZE_RELADDR + 1
      SIZE_OP_REPEAT_INC = SIZE_OPCODE + SIZE_MEMNUM
      SIZE_OP_REPEAT_INC_NG = SIZE_OPCODE + SIZE_MEMNUM
      SIZE_OP_PUSH_POS = SIZE_OPCODE
      SIZE_OP_PUSH_POS_NOT = SIZE_OPCODE + SIZE_RELADDR
      SIZE_OP_POP_POS = SIZE_OPCODE
      SIZE_OP_FAIL_POS = SIZE_OPCODE
      SIZE_OP_SET_OPTION = SIZE_OPCODE + SIZE_OPTION
      SIZE_OP_SET_OPTION_PUSH = SIZE_OPCODE + SIZE_OPTION
      SIZE_OP_FAIL = SIZE_OPCODE
      SIZE_OP_MEMORY_START = SIZE_OPCODE + SIZE_MEMNUM
      SIZE_OP_MEMORY_START_PUSH = SIZE_OPCODE + SIZE_MEMNUM
      SIZE_OP_MEMORY_END_PUSH = SIZE_OPCODE + SIZE_MEMNUM
      SIZE_OP_MEMORY_END_PUSH_REC = SIZE_OPCODE + SIZE_MEMNUM
      SIZE_OP_MEMORY_END = SIZE_OPCODE + SIZE_MEMNUM
      SIZE_OP_MEMORY_END_REC = SIZE_OPCODE + SIZE_MEMNUM
      SIZE_OP_PUSH_STOP_BT = SIZE_OPCODE
      SIZE_OP_POP_STOP_BT = SIZE_OPCODE
      SIZE_OP_NULL_CHECK_START = SIZE_OPCODE + SIZE_MEMNUM
      SIZE_OP_NULL_CHECK_END = SIZE_OPCODE + SIZE_MEMNUM
      SIZE_OP_LOOK_BEHIND = SIZE_OPCODE + SIZE_LENGTH
      SIZE_OP_PUSH_LOOK_BEHIND_NOT = SIZE_OPCODE + SIZE_RELADDR + SIZE_LENGTH
      SIZE_OP_FAIL_LOOK_BEHIND_NOT = SIZE_OPCODE
      SIZE_OP_CALL = SIZE_OPCODE + SIZE_ABSADDR
      SIZE_OP_RETURN = SIZE_OPCODE
      SIZE_OP_CONDITION = SIZE_OPCODE + SIZE_MEMNUM + SIZE_RELADDR
      SIZE_OP_PUSH_ABSENT_POS = SIZE_OPCODE
      SIZE_OP_ABSENT = SIZE_OPCODE + SIZE_RELADDR
      SIZE_OP_ABSENT_END = SIZE_OPCODE

      QUANTIFIER_EXPAND_LIMIT_SIZE = 50
    end

    # The byte code under construction (the BBuf of regex_t).
    class Code
      attr_reader :bytes

      def initialize = @bytes = "".b

      def used = @bytes.bytesize
      def add_opcode(op) = @bytes << op.chr
      def add_rel_addr(addr) = @bytes << [addr].pack("l<")
      def add_abs_addr(addr) = @bytes << [addr].pack("l<")
      def add_length(len) = @bytes << [len].pack("l<")
      def add_mem_num(num) = @bytes << [num].pack("s<")
      def add_option(option) = @bytes << [option].pack("L<")
      def add_bytes(s) = @bytes << s.b

      def add_bitset(bs)
        @bytes << Array.new(Op::SIZE_BITSET) { |i| (bs >> (8 * i)) & 0xff }.pack("C*")
      end

      def add_opcode_rel_addr(op, addr)
        add_opcode(op)
        add_rel_addr(addr)
      end

      # BBUF_WRITE of an absolute address at `offset`.
      def write_abs_addr(offset, addr) = @bytes.bytesplice(offset, Op::SIZE_ABSADDR, [addr].pack("l<"))
    end

    # compile_tree and compile_length_tree over `reg`.
    class Compiler
      include Op

      def initialize(reg)
        @reg = reg
        @enc = reg.enc
        @code = reg.code
      end

      def need_str_len_op_exact?(op) = [EXACTN, EXACTMB2N, EXACTMB3N, EXACTMBN, EXACTN_IC].include?(op)

      # roomof(byte_len, mb_len)
      def roomof(n, m) = (n + m - 1) / m

      def select_str_opcode(mb_len, byte_len, ignore_case)
        str_len = roomof(byte_len, mb_len)
        if ignore_case
          str_len == 1 ? EXACT1_IC : EXACTN_IC
        else
          case mb_len
          when 1
            case str_len
            when 1 then EXACT1
            when 2 then EXACT2
            when 3 then EXACT3
            when 4 then EXACT4
            when 5 then EXACT5
            else EXACTN
            end
          when 2
            case str_len
            when 1 then EXACTMB2N1
            when 2 then EXACTMB2N2
            when 3 then EXACTMB2N3
            else EXACTMB2N
            end
          when 3 then EXACTMB3N
          else EXACTMBN
          end
        end
      end

      def compile_tree_empty_check(node, empty_info)
        saved_num_null_check = @reg.num_null_check
        if empty_info != 0
          @code.add_opcode(NULL_CHECK_START)
          @code.add_mem_num(@reg.num_null_check) # NULL CHECK ID
          @reg.num_null_check += 1
          raise Error.new(Err::TOO_MANY_NULL_CHECK) if @reg.num_null_check >= 0x8000
        end

        compile_tree(node)

        if empty_info != 0
          case empty_info
          when TargetEmpty::IS_EMPTY then @code.add_opcode(NULL_CHECK_END)
          when TargetEmpty::IS_EMPTY_MEM then @code.add_opcode(NULL_CHECK_END_MEMST)
          when TargetEmpty::IS_EMPTY_REC then @code.add_opcode(NULL_CHECK_END_MEMST_PUSH)
          end
          @code.add_mem_num(saved_num_null_check) # NULL CHECK ID
        end
      end

      def compile_call(node)
        @code.add_opcode(CALL)
        node.unset_addr_list << [@code.used, node.target]
        @code.add_abs_addr(0) # dummy addr.
      end

      def compile_tree_n_times(node, n) = n.times { compile_tree(node) }

      def add_compile_string_length(mb_len, byte_len, ignore_case)
        op = select_str_opcode(mb_len, byte_len, ignore_case)
        len = SIZE_OPCODE
        len += SIZE_LENGTH if op == EXACTMBN
        len += SIZE_LENGTH if need_str_len_op_exact?(op)
        len + byte_len
      end

      def add_compile_string(s, mb_len, byte_len, ignore_case)
        op = select_str_opcode(mb_len, byte_len, ignore_case)
        @code.add_opcode(op)
        @code.add_length(mb_len) if op == EXACTMBN
        if need_str_len_op_exact?(op)
          @code.add_length(op == EXACTN_IC ? byte_len : byte_len / mb_len)
        end
        @code.add_bytes(s)
      end

      # The runs of same-length characters of a string node, as
      # compile_string_node and compile_length_string_node walk them.
      def each_string_run(node)
        s = node.s
        e = s.bytesize
        return if e <= 0

        ambig = node.str_ambig?
        p = prev = 0
        prev_len = @enc.enclen(s, p, e)
        p += prev_len
        blen = prev_len
        while p < e
          len = @enc.enclen(s, p, e)
          if len == prev_len || ambig
            blen += len
          else
            yield s.byteslice(prev, blen), prev_len, blen, ambig
            prev = p
            blen = len
            prev_len = len
          end
          p += len
        end
        yield s.byteslice(prev, blen), prev_len, blen, ambig
      end

      def compile_length_string_node(node)
        rlen = 0
        each_string_run(node) { |_run, mb_len, blen, ambig| rlen += add_compile_string_length(mb_len, blen, ambig) }
        rlen
      end

      def compile_length_string_raw_node(node)
        return 0 if node.s.bytesize <= 0

        add_compile_string_length(1, node.s.bytesize, false)
      end

      def compile_string_node(node)
        each_string_run(node) { |run, mb_len, blen, ambig| add_compile_string(run, mb_len, blen, ambig) }
      end

      def compile_string_raw_node(node)
        return if node.s.bytesize <= 0

        add_compile_string(node.s, 1, node.s.bytesize, false)
      end

      # The multi-byte ranges of a class as the matcher reads them: the
      # count, then the pairs, as words.
      def mbuf_bytes(mbuf) = ([mbuf.size / 2] + mbuf).pack("L<*")

      def add_multi_byte_cclass(mbuf)
        bytes = mbuf_bytes(mbuf)
        @code.add_length(bytes.bytesize)
        @code.add_bytes(bytes)
      end

      def compile_length_cclass_node(cc)
        if cc.mbuf.nil?
          SIZE_OPCODE + SIZE_BITSET
        else
          len = @enc.min_len > 1 || BitSet.empty?(cc.bs) ? SIZE_OPCODE : SIZE_OPCODE + SIZE_BITSET
          len + SIZE_LENGTH + mbuf_bytes(cc.mbuf).bytesize
        end
      end

      def compile_cclass_node(cc)
        if cc.mbuf.nil?
          @code.add_opcode(cc.cclass_not? ? CCLASS_NOT : CCLASS)
          @code.add_bitset(cc.bs)
        elsif @enc.min_len > 1 || BitSet.empty?(cc.bs)
          @code.add_opcode(cc.cclass_not? ? CCLASS_MB_NOT : CCLASS_MB)
          add_multi_byte_cclass(cc.mbuf)
        else
          @code.add_opcode(cc.cclass_not? ? CCLASS_MIX_NOT : CCLASS_MIX)
          @code.add_bitset(cc.bs)
          add_multi_byte_cclass(cc.mbuf)
        end
      end

      def entry_repeat_range(id, lower, upper)
        @reg.repeat_range[id] = [lower, upper == REPEAT_INFINITE ? 0x7fffffff : upper]
      end

      def compile_range_repeat_node(qn, target_len, empty_info)
        num_repeat = @reg.num_repeat
        @code.add_opcode(qn.greedy ? REPEAT : REPEAT_NG)
        @code.add_mem_num(num_repeat) # OP_REPEAT ID
        @reg.num_repeat += 1
        raise Error.new(Err::TOO_MANY_RANGE_REPEAT) if @reg.num_repeat >= 0x8000

        @code.add_rel_addr(target_len + SIZE_OP_REPEAT_INC)
        entry_repeat_range(num_repeat, qn.lower, qn.upper)
        compile_tree_empty_check(qn.target, empty_info)

        if @reg.num_call > 0 || qn.status?(Status::IN_REPEAT)
          @code.add_opcode(qn.greedy ? REPEAT_INC_SG : REPEAT_INC_NG_SG)
        else
          @code.add_opcode(qn.greedy ? REPEAT_INC : REPEAT_INC_NG)
        end
        @code.add_mem_num(num_repeat) # OP_REPEAT ID
      end

      def anychar_star_quantifier?(qn) = qn.greedy && qn.upper == REPEAT_INFINITE && qn.target.ntype == Node::CANY

      def compile_length_quantifier_node(qn)
        infinite = qn.upper == REPEAT_INFINITE
        empty_info = qn.target_empty_info
        tlen = compile_length_tree(qn.target)

        # anychar repeat
        if qn.target.ntype == Node::CANY && qn.greedy && infinite
          return SIZE_OP_ANYCHAR_STAR_PEEK_NEXT + tlen * qn.lower unless qn.next_head_exact.nil?

          return SIZE_OP_ANYCHAR_STAR + tlen * qn.lower
        end

        mod_tlen = empty_info != 0 ? tlen + (SIZE_OP_NULL_CHECK_START + SIZE_OP_NULL_CHECK_END) : tlen

        if infinite && (qn.lower <= 1 || tlen * qn.lower <= QUANTIFIER_EXPAND_LIMIT_SIZE)
          len = if qn.lower == 1 && tlen > QUANTIFIER_EXPAND_LIMIT_SIZE
                  SIZE_OP_JUMP
                else
                  tlen * qn.lower
                end
          if qn.greedy
            if !qn.next_head_exact.nil?
              len += SIZE_OP_PUSH_IF_PEEK_NEXT + mod_tlen + SIZE_OP_JUMP
            else
              len += SIZE_OP_PUSH + mod_tlen + SIZE_OP_JUMP
            end
          else
            len += SIZE_OP_JUMP + mod_tlen + SIZE_OP_PUSH
          end
          len
        elsif qn.upper == 0 && qn.is_referred # /(?<n>..){0}/
          SIZE_OP_JUMP + tlen
        elsif !infinite && qn.greedy && (qn.upper == 1 || (tlen + SIZE_OP_PUSH) * qn.upper <= QUANTIFIER_EXPAND_LIMIT_SIZE)
          tlen * qn.lower + (SIZE_OP_PUSH + tlen) * (qn.upper - qn.lower)
        elsif !qn.greedy && qn.upper == 1 && qn.lower == 0 # '??'
          SIZE_OP_PUSH + SIZE_OP_JUMP + tlen
        else
          SIZE_OP_REPEAT_INC + mod_tlen + SIZE_OPCODE + SIZE_RELADDR + SIZE_MEMNUM
        end
      end

      def compile_quantifier_node(qn)
        infinite = qn.upper == REPEAT_INFINITE
        empty_info = qn.target_empty_info
        tlen = compile_length_tree(qn.target)

        if anychar_star_quantifier?(qn)
          compile_tree_n_times(qn.target, qn.lower)
          if !qn.next_head_exact.nil?
            @code.add_opcode(multiline? ? ANYCHAR_ML_STAR_PEEK_NEXT : ANYCHAR_STAR_PEEK_NEXT)
            @code.add_bytes(qn.next_head_exact.s.byteslice(0, 1))
          else
            @code.add_opcode(multiline? ? ANYCHAR_ML_STAR : ANYCHAR_STAR)
          end
          return
        end

        mod_tlen = empty_info != 0 ? tlen + (SIZE_OP_NULL_CHECK_START + SIZE_OP_NULL_CHECK_END) : tlen

        if infinite && (qn.lower <= 1 || tlen * qn.lower <= QUANTIFIER_EXPAND_LIMIT_SIZE)
          if qn.lower == 1 && tlen > QUANTIFIER_EXPAND_LIMIT_SIZE
            if qn.greedy
              if !qn.next_head_exact.nil?
                @code.add_opcode_rel_addr(JUMP, SIZE_OP_PUSH_IF_PEEK_NEXT)
              else
                @code.add_opcode_rel_addr(JUMP, SIZE_OP_PUSH)
              end
            else
              @code.add_opcode_rel_addr(JUMP, SIZE_OP_JUMP)
            end
          else
            compile_tree_n_times(qn.target, qn.lower)
          end

          if qn.greedy
            if !qn.next_head_exact.nil?
              @code.add_opcode_rel_addr(PUSH_IF_PEEK_NEXT, mod_tlen + SIZE_OP_JUMP)
              @code.add_bytes(qn.next_head_exact.s.byteslice(0, 1))
              compile_tree_empty_check(qn.target, empty_info)
              @code.add_opcode_rel_addr(JUMP, -(mod_tlen + SIZE_OP_JUMP + SIZE_OP_PUSH_IF_PEEK_NEXT))
            else
              @code.add_opcode_rel_addr(PUSH, mod_tlen + SIZE_OP_JUMP)
              compile_tree_empty_check(qn.target, empty_info)
              @code.add_opcode_rel_addr(JUMP, -(mod_tlen + SIZE_OP_JUMP + SIZE_OP_PUSH))
            end
          else
            @code.add_opcode_rel_addr(JUMP, mod_tlen)
            compile_tree_empty_check(qn.target, empty_info)
            @code.add_opcode_rel_addr(PUSH, -(mod_tlen + SIZE_OP_PUSH))
          end
        elsif qn.upper == 0 && qn.is_referred # /(?<n>..){0}/
          @code.add_opcode_rel_addr(JUMP, tlen)
          compile_tree(qn.target)
        elsif !infinite && qn.greedy && (qn.upper == 1 || (tlen + SIZE_OP_PUSH) * qn.upper <= QUANTIFIER_EXPAND_LIMIT_SIZE)
          n = qn.upper - qn.lower
          compile_tree_n_times(qn.target, qn.lower)
          n.times do |i|
            @code.add_opcode_rel_addr(PUSH, (n - i) * tlen + (n - i - 1) * SIZE_OP_PUSH)
            compile_tree(qn.target)
          end
        elsif !qn.greedy && qn.upper == 1 && qn.lower == 0 # '??'
          @code.add_opcode_rel_addr(PUSH, SIZE_OP_JUMP)
          @code.add_opcode_rel_addr(JUMP, tlen)
          compile_tree(qn.target)
        else
          compile_range_repeat_node(qn, mod_tlen, empty_info)
        end
      end

      def multiline? = (@reg.options & Option::MULTILINE) != 0

      # IS_DYNAMIC_OPTION is 0: an option group compiles to its body.
      def compile_length_option_node(node)
        prev = @reg.options
        @reg.options = node.option
        tlen = compile_length_tree(node.target)
        @reg.options = prev
        tlen
      end

      def compile_option_node(node)
        prev = @reg.options
        @reg.options = node.option
        compile_tree(node.target)
        @reg.options = prev
      end

      def bt_mem_start?(n) = Onig.bit_status_at?(@reg.bt_mem_start, n)
      def bt_mem_end?(n) = Onig.bit_status_at?(@reg.bt_mem_end, n)

      def compile_length_enclose_node(node)
        return compile_length_option_node(node) if node.type == Enclose::OPTION

        tlen = node.target ? compile_length_tree(node.target) : 0

        case node.type
        when Enclose::MEMORY
          if node.status?(Status::CALLED)
            len = SIZE_OP_MEMORY_START_PUSH + tlen + SIZE_OP_CALL + SIZE_OP_JUMP + SIZE_OP_RETURN
            len += if bt_mem_end?(node.regnum)
                     node.status?(Status::RECURSION) ? SIZE_OP_MEMORY_END_PUSH_REC : SIZE_OP_MEMORY_END_PUSH
                   else
                     node.status?(Status::RECURSION) ? SIZE_OP_MEMORY_END_REC : SIZE_OP_MEMORY_END
                   end
          elsif node.status?(Status::RECURSION)
            len = SIZE_OP_MEMORY_START_PUSH
            len += tlen + (bt_mem_end?(node.regnum) ? SIZE_OP_MEMORY_END_PUSH_REC : SIZE_OP_MEMORY_END_REC)
          else
            len = bt_mem_start?(node.regnum) ? SIZE_OP_MEMORY_START_PUSH : SIZE_OP_MEMORY_START
            len += tlen + (bt_mem_end?(node.regnum) ? SIZE_OP_MEMORY_END_PUSH : SIZE_OP_MEMORY_END)
          end
          len
        when Enclose::STOP_BACKTRACK
          # USE_MATCH_CACHE: the simple-repeat form is off.
          SIZE_OP_PUSH_STOP_BT + tlen + SIZE_OP_POP_STOP_BT
        when Enclose::CONDITION
          len = SIZE_OP_CONDITION
          raise Error.new(Err::PARSER_BUG) unless node.target.ntype == Node::ALT

          x = node.target
          len += compile_length_tree(x.car) + SIZE_OP_JUMP # yes-node
          raise Error.new(Err::PARSER_BUG) if x.cdr.nil?

          x = x.cdr
          len += compile_length_tree(x.car) # no-node
          raise Error.new(Err::INVALID_CONDITION_PATTERN) unless x.cdr.nil?

          len
        when Enclose::ABSENT
          SIZE_OP_PUSH_ABSENT_POS + SIZE_OP_ABSENT + tlen + SIZE_OP_ABSENT_END
        else
          raise Error.new(Err::TYPE_BUG)
        end
      end

      def compile_enclose_node(node)
        return compile_option_node(node) if node.type == Enclose::OPTION

        case node.type
        when Enclose::MEMORY
          if node.status?(Status::CALLED)
            @code.add_opcode(CALL)
            node.call_addr = @code.used + SIZE_ABSADDR + SIZE_OP_JUMP
            node.state |= Status::ADDR_FIXED
            @code.add_abs_addr(node.call_addr)
            len = compile_length_tree(node.target)
            len += SIZE_OP_MEMORY_START_PUSH + SIZE_OP_RETURN
            len += if bt_mem_end?(node.regnum)
                     node.status?(Status::RECURSION) ? SIZE_OP_MEMORY_END_PUSH_REC : SIZE_OP_MEMORY_END_PUSH
                   else
                     node.status?(Status::RECURSION) ? SIZE_OP_MEMORY_END_REC : SIZE_OP_MEMORY_END
                   end
            @code.add_opcode_rel_addr(JUMP, len)
          end
          @code.add_opcode(bt_mem_start?(node.regnum) ? MEMORY_START_PUSH : MEMORY_START)
          @code.add_mem_num(node.regnum)
          compile_tree(node.target)
          if node.status?(Status::CALLED)
            if bt_mem_end?(node.regnum)
              @code.add_opcode(node.status?(Status::RECURSION) ? MEMORY_END_PUSH_REC : MEMORY_END_PUSH)
            else
              @code.add_opcode(node.status?(Status::RECURSION) ? MEMORY_END_REC : MEMORY_END)
            end
            @code.add_mem_num(node.regnum)
            @code.add_opcode(RETURN)
          elsif node.status?(Status::RECURSION)
            @code.add_opcode(bt_mem_end?(node.regnum) ? MEMORY_END_PUSH_REC : MEMORY_END_REC)
            @code.add_mem_num(node.regnum)
          else
            @code.add_opcode(bt_mem_end?(node.regnum) ? MEMORY_END_PUSH : MEMORY_END)
            @code.add_mem_num(node.regnum)
          end
        when Enclose::STOP_BACKTRACK
          @code.add_opcode(PUSH_STOP_BT)
          compile_tree(node.target)
          @code.add_opcode(POP_STOP_BT)
        when Enclose::CONDITION
          @code.add_opcode(CONDITION)
          @code.add_mem_num(node.regnum)
          raise Error.new(Err::PARSER_BUG) unless node.target.ntype == Node::ALT

          x = node.target
          len = compile_length_tree(x.car) # yes-node
          raise Error.new(Err::PARSER_BUG) if x.cdr.nil?

          x = x.cdr
          len2 = compile_length_tree(x.car) # no-node
          raise Error.new(Err::INVALID_CONDITION_PATTERN) unless x.cdr.nil?

          x = node.target
          @code.add_rel_addr(len + SIZE_OP_JUMP)
          compile_tree(x.car) # yes-node
          @code.add_opcode_rel_addr(JUMP, len2)
          x = x.cdr
          compile_tree(x.car) # no-node
        when Enclose::ABSENT
          len = compile_length_tree(node.target)
          @code.add_opcode(PUSH_ABSENT_POS)
          @code.add_opcode_rel_addr(ABSENT, len + SIZE_OP_ABSENT_END)
          compile_tree(node.target)
          @code.add_opcode(ABSENT_END)
        else
          raise Error.new(Err::TYPE_BUG)
        end
      end

      def compile_length_anchor_node(node)
        tlen = node.target ? compile_length_tree(node.target) : 0
        case node.type
        when Anchor::PREC_READ then SIZE_OP_PUSH_POS + tlen + SIZE_OP_POP_POS
        when Anchor::PREC_READ_NOT then SIZE_OP_PUSH_POS_NOT + tlen + SIZE_OP_FAIL_POS
        when Anchor::LOOK_BEHIND then SIZE_OP_LOOK_BEHIND + tlen
        when Anchor::LOOK_BEHIND_NOT then SIZE_OP_PUSH_LOOK_BEHIND_NOT + tlen + SIZE_OP_FAIL_LOOK_BEHIND_NOT
        else SIZE_OPCODE
        end
      end

      # The character count of a look-behind's target, as the opcode needs it.
      def look_behind_length(node)
        return node.char_len if node.char_len >= 0

        n = Tune.char_length_tree(node.target, @reg)
        raise Error.new(Err::INVALID_LOOK_BEHIND_PATTERN) if n.nil?

        n
      end

      def compile_anchor_node(node)
        case node.type
        when Anchor::BEGIN_BUF then @code.add_opcode(BEGIN_BUF)
        when Anchor::END_BUF then @code.add_opcode(END_BUF)
        when Anchor::BEGIN_LINE then @code.add_opcode(BEGIN_LINE)
        when Anchor::END_LINE then @code.add_opcode(END_LINE)
        when Anchor::SEMI_END_BUF then @code.add_opcode(SEMI_END_BUF)
        when Anchor::BEGIN_POSITION then @code.add_opcode(BEGIN_POSITION)
        when Anchor::WORD_BOUND then @code.add_opcode(node.ascii_range ? ASCII_WORD_BOUND : WORD_BOUND)
        when Anchor::NOT_WORD_BOUND then @code.add_opcode(node.ascii_range ? NOT_ASCII_WORD_BOUND : NOT_WORD_BOUND)
        when Anchor::WORD_BEGIN then @code.add_opcode(node.ascii_range ? ASCII_WORD_BEGIN : WORD_BEGIN)
        when Anchor::WORD_END then @code.add_opcode(node.ascii_range ? ASCII_WORD_END : WORD_END)
        when Anchor::KEEP then @code.add_opcode(KEEP)
        when Anchor::PREC_READ
          @code.add_opcode(PUSH_POS)
          compile_tree(node.target)
          @code.add_opcode(POP_POS)
        when Anchor::PREC_READ_NOT
          len = compile_length_tree(node.target)
          @code.add_opcode_rel_addr(PUSH_POS_NOT, len + SIZE_OP_FAIL_POS)
          compile_tree(node.target)
          @code.add_opcode(FAIL_POS)
        when Anchor::LOOK_BEHIND
          @code.add_opcode(LOOK_BEHIND)
          @code.add_length(look_behind_length(node))
          compile_tree(node.target)
        when Anchor::LOOK_BEHIND_NOT
          len = compile_length_tree(node.target)
          @code.add_opcode_rel_addr(PUSH_LOOK_BEHIND_NOT, len + SIZE_OP_FAIL_LOOK_BEHIND_NOT)
          @code.add_length(look_behind_length(node))
          compile_tree(node.target)
          @code.add_opcode(FAIL_LOOK_BEHIND_NOT)
        else
          raise Error.new(Err::TYPE_BUG)
        end
      end

      def ignorecase? = (@reg.options & Option::IGNORECASE) != 0

      def compile_length_tree(node)
        case node.ntype
        when Node::LIST
          len = 0
          n = node
          until n.nil?
            len += compile_length_tree(n.car)
            n = n.cdr
          end
          len
        when Node::ALT
          len = 0
          count = 0
          n = node
          until n.nil?
            len += compile_length_tree(n.car)
            count += 1
            n = n.cdr
          end
          len + (SIZE_OP_PUSH + SIZE_OP_JUMP) * (count - 1)
        when Node::STR
          node.str_raw? ? compile_length_string_raw_node(node) : compile_length_string_node(node)
        when Node::CCLASS then compile_length_cclass_node(node)
        when Node::CTYPE, Node::CANY then SIZE_OPCODE
        when Node::BREF
          if node.status?(Status::NEST_LEVEL)
            SIZE_OPCODE + SIZE_OPTION + SIZE_LENGTH + SIZE_LENGTH + (SIZE_MEMNUM * node.back_num)
          elsif node.back_num == 1
            !ignorecase? && node.backs[0] <= 2 ? SIZE_OPCODE : SIZE_OPCODE + SIZE_MEMNUM
          else
            SIZE_OPCODE + SIZE_LENGTH + (SIZE_MEMNUM * node.back_num)
          end
        when Node::CALL then SIZE_OP_CALL
        when Node::QTFR then compile_length_quantifier_node(node)
        when Node::ENCLOSE then compile_length_enclose_node(node)
        when Node::ANCHOR then compile_length_anchor_node(node)
        else
          raise Error.new(Err::TYPE_BUG)
        end
      end

      def compile_tree(node)
        case node.ntype
        when Node::LIST
          n = node
          until n.nil?
            compile_tree(n.car)
            n = n.cdr
          end
        when Node::ALT
          len = 0
          x = node
          until x.nil?
            len += compile_length_tree(x.car)
            len += SIZE_OP_PUSH + SIZE_OP_JUMP unless x.cdr.nil?
            x = x.cdr
          end
          pos = @code.used + len # goal position

          n = node
          until n.nil?
            len = compile_length_tree(n.car)
            @code.add_opcode_rel_addr(PUSH, len + SIZE_OP_JUMP) unless n.cdr.nil?
            compile_tree(n.car)
            unless n.cdr.nil?
              len = pos - (@code.used + SIZE_OP_JUMP)
              @code.add_opcode_rel_addr(JUMP, len)
            end
            n = n.cdr
          end
        when Node::STR
          node.str_raw? ? compile_string_raw_node(node) : compile_string_node(node)
        when Node::CCLASS then compile_cclass_node(node)
        when Node::CTYPE
          raise Error.new(Err::TYPE_BUG) unless node.ctype == CType::WORD

          op = if node.ascii_range
                 node.not ? NOT_ASCII_WORD : ASCII_WORD
               else
                 node.not ? NOT_WORD : WORD
               end
          @code.add_opcode(op)
        when Node::CANY
          @code.add_opcode(multiline? ? ANYCHAR_ML : ANYCHAR)
        when Node::BREF
          if node.status?(Status::NEST_LEVEL)
            @code.add_opcode(BACKREF_WITH_LEVEL)
            @code.add_option(@reg.options & Option::IGNORECASE)
            @code.add_length(node.nest_level)
            add_backref_mems(node)
          elsif node.back_num == 1
            n = node.backs[0]
            if ignorecase?
              @code.add_opcode(BACKREFN_IC)
              @code.add_mem_num(n)
            else
              case n
              when 1 then @code.add_opcode(BACKREF1)
              when 2 then @code.add_opcode(BACKREF2)
              else
                @code.add_opcode(BACKREFN)
                @code.add_mem_num(n)
              end
            end
          else
            @code.add_opcode(ignorecase? ? BACKREF_MULTI_IC : BACKREF_MULTI)
            add_backref_mems(node)
          end
        when Node::CALL then compile_call(node)
        when Node::QTFR then compile_quantifier_node(node)
        when Node::ENCLOSE then compile_enclose_node(node)
        when Node::ANCHOR then compile_anchor_node(node)
        end
      end

      # the `add_bacref_mems:` label: the count, then the numbers last first.
      def add_backref_mems(node)
        @code.add_length(node.back_num)
        (node.back_num - 1).downto(0) { |i| @code.add_mem_num(node.backs[i]) }
      end

      # unset_addr_list_fix: every call's dummy address filled in.
      def fix_unset_addrs(list)
        list.each do |offset, target|
          raise Error.new(Err::PARSER_BUG) unless target.status?(Status::ADDR_FIXED)

          @code.write_abs_addr(offset, target.call_addr)
        end
      end
    end
  end
end
