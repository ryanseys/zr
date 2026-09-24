# The byte code listed as onig_print_compiled_byte_code lists it
# (regcomp.c:6155-6570), for the checks and for reading a compile.
class Regexp
  module Onig
    module Disasm
      ARG_SPECIAL = -1
      ARG_NON = 0
      ARG_RELADDR = 1
      ARG_ABSADDR = 2
      ARG_LENGTH = 3
      ARG_MEMNUM = 4
      ARG_OPTION = 5

      INFO = {
        Op::FINISH => ["finish", ARG_NON],
        Op::END_ => ["end", ARG_NON],
        Op::EXACT1 => ["exact1", ARG_SPECIAL],
        Op::EXACT2 => ["exact2", ARG_SPECIAL],
        Op::EXACT3 => ["exact3", ARG_SPECIAL],
        Op::EXACT4 => ["exact4", ARG_SPECIAL],
        Op::EXACT5 => ["exact5", ARG_SPECIAL],
        Op::EXACTN => ["exactn", ARG_SPECIAL],
        Op::EXACTMB2N1 => ["exactmb2-n1", ARG_SPECIAL],
        Op::EXACTMB2N2 => ["exactmb2-n2", ARG_SPECIAL],
        Op::EXACTMB2N3 => ["exactmb2-n3", ARG_SPECIAL],
        Op::EXACTMB2N => ["exactmb2-n", ARG_SPECIAL],
        Op::EXACTMB3N => ["exactmb3n", ARG_SPECIAL],
        Op::EXACTMBN => ["exactmbn", ARG_SPECIAL],
        Op::EXACT1_IC => ["exact1-ic", ARG_SPECIAL],
        Op::EXACTN_IC => ["exactn-ic", ARG_SPECIAL],
        Op::CCLASS => ["cclass", ARG_SPECIAL],
        Op::CCLASS_MB => ["cclass-mb", ARG_SPECIAL],
        Op::CCLASS_MIX => ["cclass-mix", ARG_SPECIAL],
        Op::CCLASS_NOT => ["cclass-not", ARG_SPECIAL],
        Op::CCLASS_MB_NOT => ["cclass-mb-not", ARG_SPECIAL],
        Op::CCLASS_MIX_NOT => ["cclass-mix-not", ARG_SPECIAL],
        Op::ANYCHAR => ["anychar", ARG_NON],
        Op::ANYCHAR_ML => ["anychar-ml", ARG_NON],
        Op::ANYCHAR_STAR => ["anychar*", ARG_NON],
        Op::ANYCHAR_ML_STAR => ["anychar-ml*", ARG_NON],
        Op::ANYCHAR_STAR_PEEK_NEXT => ["anychar*-peek-next", ARG_SPECIAL],
        Op::ANYCHAR_ML_STAR_PEEK_NEXT => ["anychar-ml*-peek-next", ARG_SPECIAL],
        Op::WORD => ["word", ARG_NON],
        Op::NOT_WORD => ["not-word", ARG_NON],
        Op::WORD_BOUND => ["word-bound", ARG_NON],
        Op::NOT_WORD_BOUND => ["not-word-bound", ARG_NON],
        Op::WORD_BEGIN => ["word-begin", ARG_NON],
        Op::WORD_END => ["word-end", ARG_NON],
        Op::ASCII_WORD => ["ascii-word", ARG_NON],
        Op::NOT_ASCII_WORD => ["not-ascii-word", ARG_NON],
        Op::ASCII_WORD_BOUND => ["ascii-word-bound", ARG_NON],
        Op::NOT_ASCII_WORD_BOUND => ["not-ascii-word-bound", ARG_NON],
        Op::ASCII_WORD_BEGIN => ["ascii-word-begin", ARG_NON],
        Op::ASCII_WORD_END => ["ascii-word-end", ARG_NON],
        Op::BEGIN_BUF => ["begin-buf", ARG_NON],
        Op::END_BUF => ["end-buf", ARG_NON],
        Op::BEGIN_LINE => ["begin-line", ARG_NON],
        Op::END_LINE => ["end-line", ARG_NON],
        Op::SEMI_END_BUF => ["semi-end-buf", ARG_NON],
        Op::BEGIN_POSITION => ["begin-position", ARG_NON],
        Op::BACKREF1 => ["backref1", ARG_NON],
        Op::BACKREF2 => ["backref2", ARG_NON],
        Op::BACKREFN => ["backrefn", ARG_MEMNUM],
        Op::BACKREFN_IC => ["backrefn-ic", ARG_SPECIAL],
        Op::BACKREF_MULTI => ["backref_multi", ARG_SPECIAL],
        Op::BACKREF_MULTI_IC => ["backref_multi-ic", ARG_SPECIAL],
        Op::BACKREF_WITH_LEVEL => ["backref_at_level", ARG_SPECIAL],
        Op::MEMORY_START_PUSH => ["mem-start-push", ARG_MEMNUM],
        Op::MEMORY_START => ["mem-start", ARG_MEMNUM],
        Op::MEMORY_END_PUSH => ["mem-end-push", ARG_MEMNUM],
        Op::MEMORY_END_PUSH_REC => ["mem-end-push-rec", ARG_MEMNUM],
        Op::MEMORY_END => ["mem-end", ARG_MEMNUM],
        Op::MEMORY_END_REC => ["mem-end-rec", ARG_MEMNUM],
        Op::SET_OPTION_PUSH => ["set-option-push", ARG_OPTION],
        Op::SET_OPTION => ["set-option", ARG_OPTION],
        Op::KEEP => ["keep", ARG_NON],
        Op::FAIL => ["fail", ARG_NON],
        Op::JUMP => ["jump", ARG_RELADDR],
        Op::PUSH => ["push", ARG_RELADDR],
        Op::POP => ["pop", ARG_NON],
        Op::PUSH_OR_JUMP_EXACT1 => ["push-or-jump-e1", ARG_SPECIAL],
        Op::PUSH_IF_PEEK_NEXT => ["push-if-peek-next", ARG_SPECIAL],
        Op::REPEAT => ["repeat", ARG_SPECIAL],
        Op::REPEAT_NG => ["repeat-ng", ARG_SPECIAL],
        Op::REPEAT_INC => ["repeat-inc", ARG_MEMNUM],
        Op::REPEAT_INC_NG => ["repeat-inc-ng", ARG_MEMNUM],
        Op::REPEAT_INC_SG => ["repeat-inc-sg", ARG_MEMNUM],
        Op::REPEAT_INC_NG_SG => ["repeat-inc-ng-sg", ARG_MEMNUM],
        Op::NULL_CHECK_START => ["null-check-start", ARG_MEMNUM],
        Op::NULL_CHECK_END => ["null-check-end", ARG_MEMNUM],
        Op::NULL_CHECK_END_MEMST => ["null-check-end-memst", ARG_MEMNUM],
        Op::NULL_CHECK_END_MEMST_PUSH => ["null-check-end-memst-push", ARG_MEMNUM],
        Op::PUSH_POS => ["push-pos", ARG_NON],
        Op::POP_POS => ["pop-pos", ARG_NON],
        Op::PUSH_POS_NOT => ["push-pos-not", ARG_RELADDR],
        Op::FAIL_POS => ["fail-pos", ARG_NON],
        Op::PUSH_STOP_BT => ["push-stop-bt", ARG_NON],
        Op::POP_STOP_BT => ["pop-stop-bt", ARG_NON],
        Op::LOOK_BEHIND => ["look-behind", ARG_SPECIAL],
        Op::PUSH_LOOK_BEHIND_NOT => ["push-look-behind-not", ARG_SPECIAL],
        Op::FAIL_LOOK_BEHIND_NOT => ["fail-look-behind-not", ARG_NON],
        Op::PUSH_ABSENT_POS => ["push-absent-pos", ARG_NON],
        Op::ABSENT => ["absent", ARG_RELADDR],
        Op::ABSENT_END => ["absent-end", ARG_NON],
        Op::CALL => ["call", ARG_ABSADDR],
        Op::RETURN => ["return", ARG_NON],
        Op::CONDITION => ["condition", ARG_SPECIAL],
      }.freeze

      # A reader over the byte code.
      class Cursor
        attr_accessor :p

        def initialize(bytes, p = 0)
          @bytes = bytes
          @p = p
        end

        def byte = @bytes.getbyte(@p).tap { @p += 1 }
        def rel_addr = @bytes.byteslice(@p, 4).unpack1("l<").tap { @p += 4 }
        alias abs_addr rel_addr
        alias length rel_addr
        def mem_num = @bytes.byteslice(@p, 2).unpack1("s<").tap { @p += 2 }
        def option = @bytes.byteslice(@p, 4).unpack1("L<").tap { @p += 4 }
        def code_point = @bytes.byteslice(@p, 4).unpack1("L<")
        def bytes(n) = @bytes.byteslice(@p, n).tap { @p += n }
        def end? = @p >= @bytes.bytesize
        def bitset_on_num = bytes(32).unpack("C*").sum { |b| b.to_s(2).count("1") }
      end

      def self.p_string(s) = ":#{s}"
      def self.p_len_string(len, mb_len, s) = ":#{len}:#{s.byteslice(0, len * mb_len)}"
      def self.rel(addr) = "(#{addr >= 0 ? "+" : ""}#{addr})"

      # One instruction at the cursor, as "[name:args]".
      def self.instruction(cur, enc)
        op = cur.byte
        name, arg_type = INFO.fetch(op, ["?#{op}", ARG_NON])
        out = "[#{name}"
        if arg_type != ARG_SPECIAL
          case arg_type
          when ARG_RELADDR then out << ":#{rel(cur.rel_addr)}"
          when ARG_ABSADDR then out << ":(#{cur.abs_addr})"
          when ARG_LENGTH then out << ":#{cur.length}"
          when ARG_MEMNUM then out << ":#{cur.mem_num}"
          when ARG_OPTION then out << ":#{cur.option}"
          end
        else
          case op
          when Op::EXACT1, Op::ANYCHAR_STAR_PEEK_NEXT, Op::ANYCHAR_ML_STAR_PEEK_NEXT then out << p_string(cur.bytes(1))
          when Op::EXACT2 then out << p_string(cur.bytes(2))
          when Op::EXACT3 then out << p_string(cur.bytes(3))
          when Op::EXACT4 then out << p_string(cur.bytes(4))
          when Op::EXACT5 then out << p_string(cur.bytes(5))
          when Op::EXACTN
            len = cur.length
            out << p_len_string(len, 1, cur.bytes(len))
          when Op::EXACTMB2N1 then out << p_string(cur.bytes(2))
          when Op::EXACTMB2N2 then out << p_string(cur.bytes(4))
          when Op::EXACTMB2N3 then out << p_string(cur.bytes(6))
          when Op::EXACTMB2N
            len = cur.length
            out << p_len_string(len, 2, cur.bytes(len * 2))
          when Op::EXACTMB3N
            len = cur.length
            out << p_len_string(len, 3, cur.bytes(len * 3))
          when Op::EXACTMBN
            mb_len = cur.length
            len = cur.length
            out << ":#{mb_len}:#{len}:#{cur.bytes(len * mb_len)}"
          when Op::EXACT1_IC
            len = enc.enclen(cur.instance_variable_get(:@bytes), cur.p, cur.instance_variable_get(:@bytes).bytesize)
            out << p_string(cur.bytes(len))
          when Op::EXACTN_IC
            len = cur.length
            out << p_len_string(len, 1, cur.bytes(len))
          when Op::CCLASS, Op::CCLASS_NOT
            out << ":#{cur.bitset_on_num}"
          when Op::CCLASS_MB, Op::CCLASS_MB_NOT
            len = cur.length
            code = cur.code_point
            cur.bytes(len)
            out << ":#{code}:#{len}"
          when Op::CCLASS_MIX, Op::CCLASS_MIX_NOT
            n = cur.bitset_on_num
            len = cur.length
            code = cur.code_point
            cur.bytes(len)
            out << ":#{n}:#{code}:#{len}"
          when Op::BACKREFN_IC then out << ":#{cur.mem_num}"
          when Op::BACKREF_MULTI_IC, Op::BACKREF_MULTI
            out << " "
            len = cur.length
            out << Array.new(len) { cur.mem_num }.join(", ")
          when Op::BACKREF_WITH_LEVEL
            out << ":#{cur.option}"
            out << ":#{cur.length}"
            out << " "
            len = cur.length
            out << Array.new(len) { cur.mem_num }.join(", ")
          when Op::REPEAT, Op::REPEAT_NG
            mem = cur.mem_num
            addr = cur.rel_addr
            out << ":#{mem}:#{addr}"
          when Op::PUSH_OR_JUMP_EXACT1, Op::PUSH_IF_PEEK_NEXT
            addr = cur.rel_addr
            out << ":#{rel(addr)}" << p_string(cur.bytes(1))
          when Op::LOOK_BEHIND then out << ":#{cur.length}"
          when Op::PUSH_LOOK_BEHIND_NOT
            addr = cur.rel_addr
            len = cur.length
            out << ":#{len}:#{rel(addr)}"
          when Op::CONDITION
            mem = cur.mem_num
            addr = cur.rel_addr
            out << ":#{mem}:#{rel(addr)}"
          else
            out << "?"
          end
        end
        out << "]"
      end

      # print_compiled_byte_code_list: "code length: N" then five
      # instructions a line, each with its offset.
      def self.listing(reg)
        bytes = reg.code.bytes
        cur = Cursor.new(bytes)
        out = "code length: #{bytes.bytesize}"
        ncode = -1
        until cur.end?
          ncode += 1
          out << (ncode % 5 == 0 ? "\n#{cur.p}:" : " #{cur.p}:")
          out << instruction(cur, reg.enc)
        end
        out << "\n"
      end

      OPTIMIZE_NAMES = %w[NONE EXACT EXACT_BM EXACT_BM_NOT_REV EXACT_IC MAP EXACT_BM_IC EXACT_BM_NOT_REV_IC].freeze

      def self.anchor_text(anchor)
        names = []
        names << "begin-buf" if (anchor & Anchor::BEGIN_BUF) != 0
        names << "begin-line" if (anchor & Anchor::BEGIN_LINE) != 0
        names << "begin-pos" if (anchor & Anchor::BEGIN_POSITION) != 0
        names << "end-buf" if (anchor & Anchor::END_BUF) != 0
        names << "semi-end-buf" if (anchor & Anchor::SEMI_END_BUF) != 0
        names << "end-line" if (anchor & Anchor::END_LINE) != 0
        names << "anychar-star" if (anchor & Anchor::ANYCHAR_STAR) != 0
        names << "anychar-star-ml" if (anchor & Anchor::ANYCHAR_STAR_ML) != 0
        "[#{names.join(", ")}]"
      end

      def self.distance(d) = d == INFINITE_DISTANCE ? "inf" : "(#{d})"

      # print_optimize_info
      def self.optimize_info(reg)
        out = "optimize: #{OPTIMIZE_NAMES[reg.optimize]}\n"
        out << "  anchor: #{anchor_text(reg.anchor)}"
        out << "#{distance(reg.anchor_dmin)}-#{distance(reg.anchor_dmax)}" if (reg.anchor & Anchor::END_BUF_MASK) != 0
        out << "\n"
        out << "  sub anchor: #{anchor_text(reg.sub_anchor)}\n" if reg.optimize != 0
        out << "\n"
        if reg.exact
          out << "exact: [#{reg.exact}]: length: #{reg.exact.bytesize}\n"
        elsif reg.optimize == Optimize::OPTIMIZE_MAP
          n = reg.map.count { |v| v != 0 }
          out << "map: n=#{n}\n"
          if n > 0
            cells = []
            reg.map.each_with_index do |v, i|
              next if v == 0

              cells << (reg.enc.max_len == 1 && reg.enc.code_ctype?(i, CType::PRINT) ? i.chr : i.to_s)
            end
            out << "[#{cells.join(", ")}]\n"
          end
        end
        out
      end
    end
  end
end
