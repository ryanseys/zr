# The parse tree Onigmo builds (regparse.h's Node union) and what it
# is built with: the scan environment, the bit sets and code range
# buffers of a character class, and the name table of a pattern. A
# port of regparse.c:120-2100 under the BSD-2-Clause license
# reproduced in regexp.rb.
class Regexp
  module Onig
    # One node of the tree: the C's union as one class, so that a node
    # can change kind in place as the C's do (`*pnode = *cnode`,
    # SET_NTYPE), with the fields of every kind.
    class Node
      STR = 0
      CCLASS = 1
      CTYPE = 2
      CANY = 3
      BREF = 4
      QTFR = 5
      ENCLOSE = 6
      ANCHOR = 7
      LIST = 8
      ALT = 9
      CALL = 10

      SIMPLE = [STR, CCLASS, CTYPE, CANY, BREF].freeze

      # The kind, then every field of every kind (regparse.h).
      attr_accessor :ntype,
                    :s, :flag,                                        # STR: the bytes, NSTR_* flags
                    :flags, :bs, :mbuf,                               # CCLASS: FLAG_NCCLASS_NOT, a 256-bit set, the code ranges
                    :ctype, :not, :ascii_range,                       # CTYPE (ascii_range: ANCHOR too)
                    :state, :target, :lower, :upper, :greedy,         # QTFR
                    :target_empty_info, :head_exact, :next_head_exact, :is_referred,
                    :type, :regnum, :option, :call_addr,              # ENCLOSE (type: ANCHOR too)
                    :min_len, :max_len, :char_len, :opt_count,
                    :back_num, :backs, :nest_level,                   # BREF
                    :car, :cdr,                                       # LIST, ALT
                    :group_num, :name, :unset_addr_list               # CALL

      FLAG_NCCLASS_NOT = 1

      def initialize(ntype) = @ntype = ntype

      def simple? = SIMPLE.include?(@ntype)

      FIELDS = %i[ntype s flag flags bs mbuf ctype not ascii_range state target lower upper greedy
                  target_empty_info head_exact next_head_exact is_referred type regnum option call_addr
                  min_len max_len char_len opt_count back_num backs nest_level car cdr
                  group_num name unset_addr_list].freeze

      # The C's struct copy: every field of `other`, its kind included.
      # Field by field: the compiled core keeps no ivar table to reflect on.
      def copy_from!(other)
        FIELDS.each { |field| send(:"#{field}=", other.send(field)) }
        self
      end

      # swap_node (regcomp.c): the two nodes exchange their contents.
      def swap!(other)
        mine = Node.new(@ntype).copy_from!(self)
        copy_from!(other)
        other.copy_from!(mine)
      end

      # ---- constructors, as regparse.c's node_new_* ----

      def self.str(bytes)
        node = new(STR)
        node.s = bytes.b
        node.flag = 0
        node
      end

      def self.str_raw(bytes) = str(bytes).tap { |n| n.flag |= StrFlag::RAW }
      def self.empty = str("".b)
      def self.str_raw_char(byte) = str_raw(byte.chr.b)

      def self.cclass
        node = new(CCLASS)
        node.flags = 0
        node.bs = 0
        node.mbuf = nil
        node
      end

      def self.ctype(type, not_, ascii_range)
        node = new(CTYPE)
        node.ctype = type
        node.not = not_
        node.ascii_range = ascii_range
        node
      end

      def self.anychar = new(CANY)

      def self.list(left, right)
        node = new(LIST)
        node.car = left
        node.cdr = right
        node
      end

      def self.alt(left, right)
        node = new(ALT)
        node.car = left
        node.cdr = right
        node
      end

      # onig_node_list_add: `x` appended to `list`; the new cons cell.
      def self.list_add(list, x)
        n = list(x, nil)
        unless list.nil?
          list = list.cdr until list.cdr.nil?
          list.cdr = n
        end
        n
      end

      def self.anchor(type)
        node = new(ANCHOR)
        node.type = type
        node.target = nil
        node.char_len = -1
        node.ascii_range = false
        node
      end

      def self.backref(backrefs, by_name, exist_level, nest_level, env)
        node = new(BREF)
        node.state = 0
        node.back_num = backrefs.size
        node.state |= Status::NAME_REF if by_name
        if exist_level
          node.state |= Status::NEST_LEVEL
          node.nest_level = nest_level
        end
        backrefs.each do |ref|
          if ref <= env.num_mem && env.mem_nodes[ref].nil?
            node.state |= Status::RECURSION # /...(\1).../
            break
          end
        end
        node.backs = backrefs.dup
        node
      end

      def self.call(name, gnum)
        node = new(CALL)
        node.state = 0
        node.target = nil
        node.name = name
        node.group_num = gnum # call by number if gnum != 0
        node
      end

      def self.quantifier(lower, upper, by_number)
        node = new(QTFR)
        node.state = 0
        node.target = nil
        node.lower = lower
        node.upper = upper
        node.greedy = true
        node.target_empty_info = TargetEmpty::ISNOT_EMPTY
        node.head_exact = nil
        node.next_head_exact = nil
        node.is_referred = false
        node.state |= Status::BY_NUMBER if by_number
        node
      end

      def self.enclose(type)
        node = new(ENCLOSE)
        node.type = type
        node.state = 0
        node.regnum = 0
        node.option = 0
        node.target = nil
        node.call_addr = -1
        node.opt_count = 0
        node
      end

      def self.enclose_memory(option, named)
        node = enclose(Enclose::MEMORY)
        node.state |= Status::NAMED_GROUP if named
        node.option = option
        node
      end

      def self.option(option)
        node = enclose(Enclose::OPTION)
        node.option = option
        node
      end

      # ---- string nodes ----

      def str_cat(bytes) = @s << bytes.b
      def str_set(bytes) = @s = bytes.b
      def str_clear = (@s = "".b; @flag = 0)
      def str_len = @s.bytesize
      def str_raw? = (@flag & StrFlag::RAW) != 0
      def str_ambig? = (@flag & StrFlag::AMBIG) != 0
      def str_dont_get_opt_info? = (@flag & StrFlag::DONT_GET_OPT_INFO) != 0

      # str_node_split_last_char: the last character cut off into a
      # new node, or nil when there is only one.
      def str_split_last_char(enc)
        return nil unless @s.bytesize > 0

        p = enc.prev_char_head(@s, 0, @s.bytesize, @s.bytesize)
        return nil unless p && p > 0

        n = Node.str(@s.byteslice(p, @s.bytesize - p))
        n.flag |= StrFlag::RAW if str_raw?
        @s = @s.byteslice(0, p)
        n
      end

      def str_can_be_split?(enc)
        @s.bytesize > 0 && enc.enclen(@s, 0, @s.bytesize) < @s.bytesize
      end

      # ---- character classes ----

      def cclass_not? = (@flags & FLAG_NCCLASS_NOT) != 0
      def cclass_set_not = @flags |= FLAG_NCCLASS_NOT
      def cclass_clear_not = @flags &= ~FLAG_NCCLASS_NOT

      # ---- status bits ----

      def status?(bit) = (@state & bit) != 0
      def set_status(bit) = @state |= bit
      def clear_status(bit) = @state &= ~bit
    end

    # A 256-bit set as one Integer (regint.h's BitSet).
    module BitSet
      ALL = (1 << 256) - 1

      def self.at?(bs, pos) = (bs >> pos) & 1 == 1
      def self.set(bs, pos) = bs | (1 << pos)
      def self.clear(bs, pos) = bs & ~(1 << pos)
      def self.invert(bs) = ~bs & ALL
      def self.empty?(bs) = bs == 0
    end

    # The code ranges of a class past the single bytes (regparse.c's
    # BBuf of [n][from][to]... as a flat Array of pairs, nil for none).
    module CodeRange
      def self.count(buf) = buf.size / 2

      # add_code_range_to_buf0: the buffer with [from, to] merged in,
      # kept sorted and disjoint; a new buffer when `buf` is nil.
      def self.add_to_buf0(buf, env, from, to, checkdup)
        from, to = to, from if from > to
        data = buf || []
        n = data.size / 2

        bound = from == 0 ? 0 : n
        low = 0
        while low < bound
          x = (low + bound) >> 1
          if from - 1 > data[x * 2 + 1]
            low = x + 1
          else
            bound = x
          end
        end

        high = to == LAST_CODE_POINT ? n : low
        bound = n
        while high < bound
          x = (high + bound) >> 1
          if to + 1 >= data[x * 2]
            high = x + 1
          else
            bound = x
          end
        end

        inc_n = low + 1 - high
        raise Error.new(Err::TOO_MANY_MULTI_BYTE_RANGES) if n + inc_n > MAX_MULTI_BYTE_RANGES_NUM

        if inc_n != 1
          if checkdup && from <= data[low * 2 + 1] && (data[low * 2] <= from || data[low * 2 + 1] <= to)
            env.cc_dup_warn(from, to)
          end
          from = data[low * 2] if from > data[low * 2]
          to = data[(high - 1) * 2 + 1] if to < data[(high - 1) * 2 + 1]
        end

        if inc_n != 0
          if inc_n > 0
            # room for one more pair at `low`
            data.insert(low * 2, 0, 0) if high < n
            data.concat([0, 0]) if high >= n
          else
            # the pairs low+1 ... high-1 fold into one
            data.slice!((low + 1) * 2, (high - low - 1) * 2)
          end
        end

        data[low * 2] = from
        data[low * 2 + 1] = to
        data
      end

      def self.add_to_buf(buf, env, from, to) = add_to_buf0(buf, env, from, to, true)

      # add_code_range0
      def self.add0(buf, env, from, to, checkdup)
        if from > to
          return buf if Syntax.bv?(Syntax::ALLOW_EMPTY_RANGE_IN_CC)

          raise Error.new(Err::EMPTY_RANGE_IN_CHAR_CLASS)
        end
        add_to_buf0(buf, env, from, to, checkdup)
      end

      def self.add(buf, env, from, to) = add0(buf, env, from, to, true)

      # MBCODE_START_POS
      def self.mbcode_start_pos(enc) = enc.min_len > 1 ? 0 : 0x80

      # SET_ALL_MULTI_BYTE_RANGE
      def self.set_all_multi_byte(enc, buf, env) = add_to_buf(buf, env, mbcode_start_pos(enc), LAST_CODE_POINT)

      # not_code_range_buf: the complement, as a new buffer (or nil).
      def self.not_buf(enc, buf, env)
        return set_all_multi_byte(enc, nil, env) if buf.nil?

        n = buf.size / 2
        return set_all_multi_byte(enc, nil, env) if n <= 0

        out = nil
        pre = mbcode_start_pos(enc)
        to = 0
        n.times do |i|
          from = buf[i * 2]
          to = buf[i * 2 + 1]
          out = add_to_buf(out, env, pre, from - 1) if pre <= from - 1
          break if to == LAST_CODE_POINT

          pre = to + 1
        end
        out = add_to_buf(out, env, to + 1, LAST_CODE_POINT) if to < LAST_CODE_POINT
        out
      end

      # or_code_range_buf
      def self.or_buf(enc, buf1, not1, buf2, not2, env)
        if buf1.nil? && buf2.nil?
          return set_all_multi_byte(enc, nil, env) if not1 || not2

          return nil
        end

        buf1, not1, buf2, not2 = buf2, not2, buf1, not1 if buf2.nil?

        if buf1.nil?
          return set_all_multi_byte(enc, nil, env) if not1

          return not2 ? not_buf(enc, buf2, env) : buf2.dup
        end

        buf1, not1, buf2, not2 = buf2, not2, buf1, not1 if not1

        out = if !not2 && !not1 # 1 OR 2
                buf2.dup
              elsif !not1 # 1 OR (not 2)
                not_buf(enc, buf2, env)
              end
        (buf1.size / 2).times do |i|
          out = add_to_buf(out, env, buf1[i * 2], buf1[i * 2 + 1])
        end
        out
      end

      # and_code_range1
      def self.and_range1(buf, env, from1, to1, data)
        (data.size / 2).times do |i|
          from2 = data[i * 2]
          to2 = data[i * 2 + 1]
          if from2 < from1
            next if to2 < from1

            from1 = to2 + 1
          elsif from2 <= to1
            if to2 < to1
              buf = add_to_buf(buf, env, from1, from2 - 1) if from1 <= from2 - 1
              from1 = to2 + 1
            else
              to1 = from2 - 1
            end
          else
            from1 = from2
          end
          break if from1 > to1
        end
        buf = add_to_buf(buf, env, from1, to1) if from1 <= to1
        buf
      end

      # and_code_range_buf
      def self.and_buf(buf1, not1, buf2, not2, env)
        if buf1.nil?
          return buf2.dup if not1 && !buf2.nil? # not1 -> not2 == 0

          return nil
        elsif buf2.nil?
          return buf1.dup if not2

          return nil
        end

        buf1, not1, buf2, not2 = buf2, not2, buf1, not1 if not1

        out = nil
        n1 = buf1.size / 2
        n2 = buf2.size / 2
        if !not2 && !not1 # 1 AND 2
          n1.times do |i|
            from1 = buf1[i * 2]
            to1 = buf1[i * 2 + 1]
            n2.times do |j|
              from2 = buf2[j * 2]
              to2 = buf2[j * 2 + 1]
              break if from2 > to1
              next if to2 < from1

              out = add_to_buf(out, env, [from1, from2].max, [to1, to2].min)
            end
          end
        elsif !not1 # 1 AND (not 2)
          n1.times do |i|
            out = and_range1(out, env, buf1[i * 2], buf1[i * 2 + 1], buf2)
          end
        end
        out
      end

      # onig_is_code_in_cc_len (regexec.c): whether `code` is in the class.
      def self.code_in_cc_len?(enclen, code, cc)
        found = if enclen > 1 || code >= 256
                  cc.mbuf.nil? ? false : Unicode.in_code_range?(cc.mbuf, code)
                else
                  BitSet.at?(cc.bs, code)
                end
        cc.cclass_not? ? !found : found
      end

      def self.code_in_cc?(enc, code, cc)
        len = enc.min_len > 1 ? 2 : enc.code_to_mbclen(code)
        code_in_cc_len?(len, code, cc)
      end
    end

    # and_cclass and or_cclass (regparse.c:2262-2364): `cc` folded into
    # `dest` in place.
    module CClassOps
      def self.and(dest, cc, env)
        enc = env.enc
        not1 = dest.cclass_not?
        bsr1 = dest.bs
        buf1 = dest.mbuf
        not2 = cc.cclass_not?
        bsr2 = cc.bs
        buf2 = cc.mbuf

        bsr1 = BitSet.invert(bsr1) if not1
        bsr2 = BitSet.invert(bsr2) if not2
        bsr1 &= bsr2
        bsr1 = BitSet.invert(bsr1) if not1
        dest.bs = bsr1

        return if enc.singlebyte?

        if not1 && not2
          pbuf = CodeRange.or_buf(enc, buf1, false, buf2, false, env)
        else
          pbuf = CodeRange.and_buf(buf1, not1, buf2, not2, env)
          pbuf = CodeRange.not_buf(enc, pbuf, env) if not1
        end
        dest.mbuf = pbuf
      end

      def self.or(dest, cc, env)
        enc = env.enc
        not1 = dest.cclass_not?
        bsr1 = dest.bs
        buf1 = dest.mbuf
        not2 = cc.cclass_not?
        bsr2 = cc.bs
        buf2 = cc.mbuf

        bsr1 = BitSet.invert(bsr1) if not1
        bsr2 = BitSet.invert(bsr2) if not2
        bsr1 |= bsr2
        bsr1 = BitSet.invert(bsr1) if not1
        dest.bs = bsr1

        return if enc.singlebyte?

        if not1 && not2
          pbuf = CodeRange.and_buf(buf1, false, buf2, false, env)
        else
          pbuf = CodeRange.or_buf(enc, buf1, not1, buf2, not2, env)
          pbuf = CodeRange.not_buf(enc, pbuf, env) if not1
        end
        dest.mbuf = pbuf
      end
    end

    # A named group's entry in the name table: the group numbers under
    # the name, in the order they were defined (NameEntry).
    class NameEntry
      attr_reader :name, :back_refs

      def initialize(name)
        @name = name
        @back_refs = []
      end

      def back_num = @back_refs.size
    end

    # The pattern being compiled, as regparse and regcomp see it
    # (regex_t): what the parser records on it, and the name table.
    class Reg
      attr_accessor :options, :case_fold_flag, :enc, :num_mem, :name_table,
                    :num_repeat, :num_null_check, :num_call, :capture_history,
                    :bt_mem_start, :bt_mem_end, :stack_pop_level, :repeat_range,
                    :optimize, :threshold_len, :anchor, :anchor_dmin, :anchor_dmax,
                    :sub_anchor, :exact, :map, :dmin, :dmax, :code, :tree

      def initialize(options, enc, case_fold_flag = CASE_FOLD_DEFAULT)
        @options = options
        @enc = enc
        @case_fold_flag = case_fold_flag
        @num_mem = 0
        @name_table = nil
        @num_repeat = 0
        @num_null_check = 0
        @num_call = 0
        @capture_history = 0
        @bt_mem_start = 0
        @bt_mem_end = 0
        @stack_pop_level = 0
        @repeat_range = []
      end

      def names_clear = @name_table = nil
      def number_of_names = @name_table ? @name_table.size : 0

      def name_find(name) = @name_table && @name_table[name]

      # name_add
      def name_add(name, backref, env)
        raise Error.new(Err::EMPTY_GROUP_NAME) if name.bytesize <= 0

        e = name_find(name)
        if e.nil?
          @name_table ||= {}
          e = NameEntry.new(name)
          @name_table[name] = e
        end

        if e.back_num >= 1 && !Syntax.bv?(Syntax::ALLOW_MULTIPLEX_DEFINITION_NAME)
          raise Error.new(Err::MULTIPLEX_DEFINED_NAME, name, env.enc)
        end

        e.back_refs << backref
      end

      # onig_name_to_group_numbers: the numbers, or nil for no such name.
      def name_to_group_numbers(name)
        e = name_find(name)
        e.nil? ? nil : e.back_refs
      end

      # onig_foreach_name
      def each_name(&block)
        @name_table&.each_value { |e| block.call(e.name, e.back_refs) }
      end

      # onig_renumber_name_table
      def renumber_name_table(map)
        @name_table&.each_value { |e| e.back_refs.map! { |n| map[n] } }
      end

      # onig_noname_group_capture_is_active
      def noname_group_capture_active?
        return false if (@options & Option::DONT_CAPTURE_GROUP) != 0
        return false if number_of_names > 0 && Syntax.bv?(Syntax::CAPTURE_ONLY_NAMED_GROUP) && (@options & Option::CAPTURE_GROUP) == 0

        true
      end
    end

    # ScanEnv: what the parser carries through a pattern.
    class ScanEnv
      attr_accessor :option, :case_fold_flag, :enc, :capture_history, :bt_mem_start,
                    :bt_mem_end, :backrefed_mem, :pattern, :reg, :unset_addr_list,
                    :num_call, :num_mem, :num_named, :mem_nodes, :parse_depth,
                    :warnings_flag, :warnings

      def initialize(reg, pattern, warnings)
        @reg = reg
        @option = reg.options
        @case_fold_flag = reg.case_fold_flag
        @enc = reg.enc
        @pattern = pattern
        @warnings = warnings
        @capture_history = 0
        @bt_mem_start = 0
        @bt_mem_end = 0
        @backrefed_mem = 0
        @num_call = 0
        @num_mem = 0
        @num_named = 0
        @mem_nodes = [nil]
        @unset_addr_list = nil
        @parse_depth = 0
        @warnings_flag = 0
      end

      def pattern_end = @pattern.bytesize

      # scan_env_add_mem_entry: the next group number.
      def add_mem_entry
        need = @num_mem + 1
        raise Error.new(Err::TOO_MANY_CAPTURE_GROUPS) if need > MAX_CAPTURE_GROUP_NUM

        @mem_nodes[need] = nil
        @num_mem += 1
      end

      def set_mem_node(num, node)
        raise Error.new(Err::PARSER_BUG) unless @num_mem >= num

        @mem_nodes[num] = node
      end

      def ignorecase? = (@option & Option::IGNORECASE) != 0
      def extend? = (@option & Option::EXTEND) != 0
      def multiline? = (@option & Option::MULTILINE) != 0
      def singleline? = (@option & Option::SINGLELINE) != 0
      def ascii_range? = (@option & Option::ASCII_RANGE) != 0
      def posix_bracket_all_range? = (@option & Option::POSIX_BRACKET_ALL_RANGE) != 0
      def word_bound_all_range? = (@option & Option::WORD_BOUND_ALL_RANGE) != 0

      # onig_syntax_warn: `text` with the pattern appended as
      # onig_vsnprintf_with_pattern appends it, when it fits.
      def syntax_warn(text, verbose: false)
        @warnings.add(Warnings.with_pattern(text, @pattern, @enc), verbose: verbose)
      end

      def cc_esc_warn(c)
        return unless Syntax.bv?(Syntax::WARN_CC_OP_NOT_ESCAPED) && Syntax.bv?(Syntax::BACKSLASH_ESCAPE_IN_CC)

        syntax_warn("character class has '#{c}' without escape")
      end

      def close_bracket_without_esc_warn(c)
        syntax_warn("regular expression has '#{c}' without escape") if Syntax.bv?(Syntax::WARN_CC_OP_NOT_ESCAPED)
      end

      def cc_dup_warn(_from, _to)
        return unless Syntax.bv?(Syntax::WARN_CC_DUP) && (@warnings_flag & Syntax::WARN_CC_DUP) == 0

        @warnings_flag |= Syntax::WARN_CC_DUP
        syntax_warn("character class has duplicated range", verbose: true)
      end

      def unknown_esc_warn(c) = syntax_warn("Unknown escape \\#{c.chr} is ignored", verbose: true)
    end

    class Warnings
      WARN_BUFSIZE = 256

      # onig_vsnprintf_with_pattern: ": /pattern/" after the text, the
      # pattern's bytes written as it writes them, only when the whole
      # fits the 256-byte buffer. The answer is BINARY.
      def self.with_pattern(text, pat, enc)
        n = text.bytesize
        need = pat.bytesize * 4 + 4
        return text.b if n + need >= WARN_BUFSIZE

        out = text.b + ": /".b
        p = 0
        pat_end = pat.bytesize
        while p < pat_end
          if enc.len(pat, p, pat_end) != 1
            len = enc.enclen(pat, p, pat_end)
            if enc.min_len == 1
              out << pat.byteslice(p, len)
            else
              # UTF-16 and UTF-32: each byte as \xHH.
              len.times { |i| out << format("\\x%02x", pat.getbyte(p + i)).b }
            end
            p += len
          elsif pat.getbyte(p) == 0x5c
            out << "\\".b
            p += 1
            len = enc.enclen(pat, p, pat_end)
            out << pat.byteslice(p, len)
            p += len
          elsif pat.getbyte(p) == 0x2f
            out << "\\/".b
            p += 1
          elsif !enc.code_ctype?(pat.getbyte(p), CType::PRINT) &&
                (!enc.code_ctype?(pat.getbyte(p), CType::SPACE) || enc.code_ctype?(pat.getbyte(p), CType::CNTRL))
            out << format("\\x%02x", pat.getbyte(p)).b
            p += 1
          else
            out << pat.byteslice(p, 1)
            p += 1
          end
        end
        # re_warn formats it with rb_warn, as bytes.
        out << "/".b
      end
    end
  end
end
