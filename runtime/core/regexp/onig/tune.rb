# Onigmo's tree setup between the parse and the compile (regcomp.c:
# 1895-4200): group renumbering, match lengths, subexpression calls,
# look-behind checks, the possessive rewrite, case fold expansion of
# strings, and setup_tree itself. A port under the BSD-2-Clause license
# reproduced in regexp.rb.
class Regexp
  module Onig
    module Tune
      IN_ALT = 1 << 0
      IN_NOT = 1 << 1
      IN_REPEAT = 1 << 2
      IN_VAR_REPEAT = 1 << 3
      IN_CALL = 1 << 4
      IN_RECCALL = 1 << 5
      IN_LOOK_BEHIND = 1 << 6

      RECURSION_EXIST = 1
      RECURSION_INFINITE = 2
      FOUND_CALLED_NODE = 1

      GET_CHAR_LEN_VARLEN = -1
      GET_CHAR_LEN_TOP_ALT_VARLEN = -2

      EXPAND_STRING_MAX_LENGTH = 100
      THRESHOLD_CASE_FOLD_ALT_FOR_EXPANSION = 8

      module_function

      # ---- named groups: unnamed groups stop capturing ----

      # noname_disable_map: the node with its unnamed groups gone and its
      # named ones renumbered; `map[old]` takes the new number.
      def noname_disable_map(node, map, counter)
        case node.ntype
        when Node::LIST, Node::ALT
          n = node
          until n.nil?
            n.car = noname_disable_map(n.car, map, counter)
            n = n.cdr
          end
        when Node::QTFR
          old = node.target
          node.target = noname_disable_map(old, map, counter)
          Parser.reduce_nested_quantifier(node, node.target) if !node.target.equal?(old) && node.target.ntype == Node::QTFR
        when Node::ENCLOSE
          if node.type == Enclose::MEMORY
            if node.status?(Status::NAMED_GROUP)
              counter[0] += 1
              map[node.regnum] = counter[0]
              node.regnum = counter[0]
            elsif node.regnum != 0
              target = node.target
              node.target = nil
              return noname_disable_map(target, map, counter)
            end
          end
          node.target = noname_disable_map(node.target, map, counter)
        when Node::ANCHOR
          node.target = noname_disable_map(node.target, map, counter) unless node.target.nil?
        end
        node
      end

      def renumber_node_backref(node, map, num_mem)
        raise Error.new(Err::NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED) unless node.status?(Status::NAME_REF)

        backs = []
        node.backs.each do |b|
          raise Error.new(Err::INVALID_BACKREF) if b > num_mem

          n = map[b]
          backs << n if n > 0
        end
        node.backs = backs
        node.back_num = backs.size
      end

      def renumber_by_map(node, map, num_mem)
        case node.ntype
        when Node::LIST, Node::ALT
          n = node
          until n.nil?
            renumber_by_map(n.car, map, num_mem)
            n = n.cdr
          end
        when Node::QTFR
          renumber_by_map(node.target, map, num_mem)
        when Node::ENCLOSE
          if node.type == Enclose::CONDITION
            raise Error.new(Err::INVALID_BACKREF) if node.regnum > num_mem

            node.regnum = map[node.regnum]
          end
          renumber_by_map(node.target, map, num_mem)
        when Node::BREF
          renumber_node_backref(node, map, num_mem)
        when Node::ANCHOR
          renumber_by_map(node.target, map, num_mem) unless node.target.nil?
        end
      end

      def numbered_ref_check(node)
        case node.ntype
        when Node::LIST, Node::ALT
          n = node
          until n.nil?
            numbered_ref_check(n.car)
            n = n.cdr
          end
        when Node::QTFR then numbered_ref_check(node.target)
        when Node::ENCLOSE then numbered_ref_check(node.target)
        when Node::BREF
          raise Error.new(Err::NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED) unless node.status?(Status::NAME_REF)
        when Node::ANCHOR
          numbered_ref_check(node.target) unless node.target.nil?
        end
      end

      # disable_noname_group_capture: the new root.
      def disable_noname_group_capture(root, reg, env)
        map = Array.new(env.num_mem + 1, 0)
        counter = [0]
        root = noname_disable_map(root, map, counter)
        renumber_by_map(root, map, env.num_mem)

        pos = 1
        (1..env.num_mem).each do |i|
          if map[i] > 0
            env.mem_nodes[pos] = env.mem_nodes[i]
            pos += 1
          end
        end

        loc = env.capture_history
        env.capture_history = 0
        (1..MAX_CAPTURE_HISTORY_GROUP).each do |i|
          env.capture_history = Onig.bit_status_on_at_simple(env.capture_history, map[i]) if Onig.bit_status_at?(loc, i)
        end

        env.num_mem = env.num_named
        reg.num_mem = env.num_named
        reg.renumber_name_table(map)
        root
      end

      # ---- match lengths ----

      # quantifiers_memory_node_info (USE_MONOMANIAC_CHECK_CAPTURES_IN_ENDLESS_REPEAT)
      def quantifiers_memory_node_info(node)
        r = 0
        case node.ntype
        when Node::LIST, Node::ALT
          n = node
          until n.nil?
            v = quantifiers_memory_node_info(n.car)
            r = v if v > r
            n = n.cdr
          end
        when Node::CALL
          return TargetEmpty::IS_EMPTY_REC if node.status?(Status::RECURSION) # tiny version

          r = quantifiers_memory_node_info(node.target)
        when Node::QTFR
          r = quantifiers_memory_node_info(node.target) if node.upper != 0
        when Node::ENCLOSE
          case node.type
          when Enclose::MEMORY then return TargetEmpty::IS_EMPTY_MEM
          when Enclose::OPTION, Enclose::STOP_BACKTRACK, Enclose::CONDITION, Enclose::ABSENT
            r = quantifiers_memory_node_info(node.target)
          end
        end
        r
      end

      def min_match_length(node, env)
        min = 0
        case node.ntype
        when Node::BREF
          return 0 if node.status?(Status::RECURSION)

          backs = node.backs
          raise Error.new(Err::INVALID_BACKREF) if backs[0] > env.num_mem

          min = min_match_length(env.mem_nodes[backs[0]], env)
          backs.drop(1).each do |b|
            raise Error.new(Err::INVALID_BACKREF) if b > env.num_mem

            tmin = min_match_length(env.mem_nodes[b], env)
            min = tmin if min > tmin
          end
        when Node::CALL
          if node.status?(Status::RECURSION)
            en = node.target
            min = en.min_len if en.status?(Status::MIN_FIXED)
          else
            min = min_match_length(node.target, env)
          end
        when Node::LIST
          n = node
          until n.nil?
            min += min_match_length(n.car, env)
            n = n.cdr
          end
        when Node::ALT
          n = node
          until n.nil?
            tmin = min_match_length(n.car, env)
            min = tmin if n.equal?(node) || min > tmin
            n = n.cdr
          end
        when Node::STR then min = node.s.bytesize
        when Node::CTYPE, Node::CCLASS, Node::CANY then min = 1
        when Node::QTFR
          if node.lower > 0
            min = min_match_length(node.target, env)
            min = Onig.distance_multiply(min, node.lower)
          end
        when Node::ENCLOSE
          case node.type
          when Enclose::MEMORY
            if node.status?(Status::MIN_FIXED)
              min = node.min_len
            elsif node.status?(Status::MARK1)
              min = 0 # recursive
            else
              node.set_status(Status::MARK1)
              begin
                min = min_match_length(node.target, env)
              ensure
                node.clear_status(Status::MARK1)
              end
              node.min_len = min
              node.set_status(Status::MIN_FIXED)
            end
          when Enclose::OPTION, Enclose::STOP_BACKTRACK, Enclose::CONDITION
            min = min_match_length(node.target, env)
          end
        end
        min
      end

      def max_match_length(node, env)
        max = 0
        case node.ntype
        when Node::LIST
          n = node
          until n.nil?
            max = Onig.distance_add(max, max_match_length(n.car, env))
            n = n.cdr
          end
        when Node::ALT
          n = node
          until n.nil?
            tmax = max_match_length(n.car, env)
            max = tmax if max < tmax
            n = n.cdr
          end
        when Node::STR then max = node.s.bytesize
        when Node::CTYPE, Node::CCLASS, Node::CANY then max = env.enc.max_len
        when Node::BREF
          return INFINITE_DISTANCE if node.status?(Status::RECURSION)

          node.backs.each do |b|
            raise Error.new(Err::INVALID_BACKREF) if b > env.num_mem

            tmax = max_match_length(env.mem_nodes[b], env)
            max = tmax if max < tmax
          end
        when Node::CALL
          max = node.status?(Status::RECURSION) ? INFINITE_DISTANCE : max_match_length(node.target, env)
        when Node::QTFR
          if node.upper != 0
            max = max_match_length(node.target, env)
            if max != 0
              max = node.upper != REPEAT_INFINITE ? Onig.distance_multiply(max, node.upper) : INFINITE_DISTANCE
            end
          end
        when Node::ENCLOSE
          case node.type
          when Enclose::MEMORY
            if node.status?(Status::MAX_FIXED)
              max = node.max_len
            elsif node.status?(Status::MARK1)
              max = INFINITE_DISTANCE
            else
              node.set_status(Status::MARK1)
              begin
                max = max_match_length(node.target, env)
              ensure
                node.clear_status(Status::MARK1)
              end
              node.max_len = max
              node.set_status(Status::MAX_FIXED)
            end
          when Enclose::OPTION, Enclose::STOP_BACKTRACK, Enclose::CONDITION
            max = max_match_length(node.target, env)
          end
        end
        max
      end

      # get_char_length_tree1: [r, len]; r is 0, GET_CHAR_LEN_VARLEN or
      # GET_CHAR_LEN_TOP_ALT_VARLEN.
      def char_length_tree1(node, reg, level)
        level += 1
        len = 0
        r = 0
        case node.ntype
        when Node::LIST
          n = node
          until n.nil?
            r, tlen = char_length_tree1(n.car, reg, level)
            break if r != 0

            len = Onig.distance_add(len, tlen)
            n = n.cdr
          end
        when Node::ALT
          varlen = false
          r, tlen = char_length_tree1(node.car, reg, level)
          n = node.cdr
          while r == 0 && !n.nil?
            r, tlen2 = char_length_tree1(n.car, reg, level)
            varlen = true if r == 0 && tlen != tlen2
            n = n.cdr
          end
          if r == 0
            if varlen
              r = level == 1 ? GET_CHAR_LEN_TOP_ALT_VARLEN : GET_CHAR_LEN_VARLEN
            else
              len = tlen
            end
          end
        when Node::STR
          s = node.s
          p = 0
          while p < s.bytesize
            p += reg.enc.enclen(s, p, s.bytesize)
            len += 1
          end
        when Node::QTFR
          if node.lower == node.upper
            r, tlen = char_length_tree1(node.target, reg, level)
            len = Onig.distance_multiply(tlen, node.lower) if r == 0
          else
            r = GET_CHAR_LEN_VARLEN
          end
        when Node::CALL
          if node.status?(Status::RECURSION)
            r = GET_CHAR_LEN_VARLEN
          else
            r, len = char_length_tree1(node.target, reg, level)
          end
        when Node::CTYPE, Node::CCLASS, Node::CANY
          len = 1
        when Node::ENCLOSE
          case node.type
          when Enclose::MEMORY
            if node.status?(Status::CLEN_FIXED)
              len = node.char_len
            else
              r, len = char_length_tree1(node.target, reg, level)
              if r == 0
                node.char_len = len
                node.set_status(Status::CLEN_FIXED)
              end
            end
          when Enclose::OPTION, Enclose::STOP_BACKTRACK, Enclose::CONDITION
            r, len = char_length_tree1(node.target, reg, level)
          end
        when Node::ANCHOR
          nil
        else
          r = GET_CHAR_LEN_VARLEN
        end
        [r, len]
      end

      # get_char_length_tree: the character count, or nil when it varies.
      def char_length_tree(node, reg)
        r, len = char_length_tree1(node, reg, 0)
        r == 0 ? len : nil
      end

      # ---- what can follow what ----

      def code_sb_word?(enc, code) = code < 128 && enc.code_ctype?(code, CType::WORD)

      # is_not_included: x is not included in y.
      def not_included?(x, y, reg)
        enc = reg.enc
        loop do
          case x.ntype
          when Node::CTYPE
            case y.ntype
            when Node::CTYPE
              return y.ctype == x.ctype && y.not != x.not && y.ascii_range == x.ascii_range
            when Node::CCLASS, Node::STR
              x, y = y, x
              next
            end
            return false
          when Node::CCLASS
            case y.ntype
            when Node::CTYPE
              return false unless y.ctype == CType::WORD

              if !y.not
                if x.mbuf.nil? && !x.cclass_not?
                  256.times do |i|
                    next unless BitSet.at?(x.bs, i)

                    if y.ascii_range
                      return false if code_sb_word?(enc, i)
                    elsif enc.code_ctype?(i, CType::WORD)
                      return false
                    end
                  end
                  return true
                end
                return false
              else
                return false unless x.mbuf.nil?

                256.times do |i|
                  is_word = y.ascii_range ? code_sb_word?(enc, i) : enc.code_ctype?(i, CType::WORD)
                  next if is_word

                  if !x.cclass_not?
                    return false if BitSet.at?(x.bs, i)
                  elsif !BitSet.at?(x.bs, i)
                    return false
                  end
                end
                return true
              end
            when Node::CCLASS
              256.times do |i|
                v = BitSet.at?(x.bs, i)
                next unless (v && !x.cclass_not?) || (!v && x.cclass_not?)

                v = BitSet.at?(y.bs, i)
                return false if (v && !y.cclass_not?) || (!v && y.cclass_not?)
              end
              return true if (x.mbuf.nil? && !x.cclass_not?) || (y.mbuf.nil? && !y.cclass_not?)

              return false
            when Node::STR
              x, y = y, x
              next
            end
            return false
          when Node::STR
            return false if x.s.bytesize == 0

            case y.ntype
            when Node::CTYPE
              return false unless y.ctype == CType::WORD

              s = x.s
              if y.ascii_range
                return enc.mbc_ascii_word?(s, 0, s.bytesize) ? y.not : !y.not
              else
                return enc.mbc_word?(s, 0, s.bytesize) ? y.not : !y.not
              end
            when Node::CCLASS
              s = x.s
              code = enc.mbc_to_code(s, 0, [s.bytesize, enc.max_len].min)
              return !CodeRange.code_in_cc?(enc, code, y)
            when Node::STR
              return false if x.str_ambig? || y.str_ambig? # tiny version

              len = [x.s.bytesize, y.s.bytesize].min
              len.times { |i| return true if x.s.getbyte(i) != y.s.getbyte(i) }
              return false
            end
            return false
          end
          return false
        end
      end

      # get_head_value_node
      def head_value_node(node, exact, reg)
        case node.ntype
        when Node::BREF, Node::ALT, Node::CANY, Node::CALL
          nil
        when Node::CTYPE, Node::CCLASS
          exact ? nil : node
        when Node::LIST
          head_value_node(node.car, exact, reg)
        when Node::STR
          return nil if node.s.bytesize <= 0

          !exact || node.str_raw? || (reg.options & Option::IGNORECASE) == 0 ? node : nil
        when Node::QTFR
          node.lower > 0 ? head_value_node(node.target, exact, reg) : nil
        when Node::ENCLOSE
          case node.type
          when Enclose::OPTION
            options = reg.options
            reg.options = node.option
            n = head_value_node(node.target, exact, reg)
            reg.options = options
            n
          when Enclose::MEMORY, Enclose::STOP_BACKTRACK, Enclose::CONDITION
            head_value_node(node.target, exact, reg)
          end
        when Node::ANCHOR
          node.type == Anchor::PREC_READ ? head_value_node(node.target, exact, reg) : nil
        end
      end

      # check_type_tree: true when a node outside the masks is found.
      def check_type_tree(node, type_mask, enclose_mask, anchor_mask)
        return true if ((1 << node.ntype) & type_mask) == 0

        case node.ntype
        when Node::LIST, Node::ALT
          n = node
          until n.nil?
            return true if check_type_tree(n.car, type_mask, enclose_mask, anchor_mask)

            n = n.cdr
          end
        when Node::QTFR
          return check_type_tree(node.target, type_mask, enclose_mask, anchor_mask)
        when Node::ENCLOSE
          return true if (node.type & enclose_mask) == 0

          return check_type_tree(node.target, type_mask, enclose_mask, anchor_mask)
        when Node::ANCHOR
          return true if (node.type & anchor_mask) == 0
          return check_type_tree(node.target, type_mask, enclose_mask, anchor_mask) if node.target
        end
        false
      end

      # ---- subexpression calls ----

      LOOKAROUNDS = [Anchor::PREC_READ, Anchor::PREC_READ_NOT, Anchor::LOOK_BEHIND, Anchor::LOOK_BEHIND_NOT].freeze

      def subexp_inf_recursive_check(node, env, head)
        r = 0
        case node.ntype
        when Node::LIST
          x = node
          until x.nil?
            ret = subexp_inf_recursive_check(x.car, env, head)
            return ret if ret == RECURSION_INFINITE

            r |= ret
            if head
              min = min_match_length(x.car, env)
              head = false if min != 0
            end
            x = x.cdr
          end
        when Node::ALT
          r = RECURSION_EXIST
          n = node
          until n.nil?
            ret = subexp_inf_recursive_check(n.car, env, head)
            return ret if ret == RECURSION_INFINITE

            r &= ret
            n = n.cdr
          end
        when Node::QTFR
          r = subexp_inf_recursive_check(node.target, env, head)
          r = 0 if r == RECURSION_EXIST && node.lower == 0
        when Node::ANCHOR
          r = subexp_inf_recursive_check(node.target, env, head) if LOOKAROUNDS.include?(node.type)
        when Node::CALL
          r = subexp_inf_recursive_check(node.target, env, head)
        when Node::ENCLOSE
          if node.status?(Status::MARK2)
            return 0
          elsif node.status?(Status::MARK1)
            return head ? RECURSION_INFINITE : RECURSION_EXIST
          else
            node.set_status(Status::MARK2)
            begin
              r = subexp_inf_recursive_check(node.target, env, head)
            ensure
              node.clear_status(Status::MARK2)
            end
          end
        end
        r
      end

      def subexp_inf_recursive_check_trav(node, env)
        case node.ntype
        when Node::LIST, Node::ALT
          n = node
          until n.nil?
            subexp_inf_recursive_check_trav(n.car, env)
            n = n.cdr
          end
        when Node::QTFR
          subexp_inf_recursive_check_trav(node.target, env)
        when Node::ANCHOR
          subexp_inf_recursive_check_trav(node.target, env) if LOOKAROUNDS.include?(node.type)
        when Node::ENCLOSE
          if node.status?(Status::RECURSION)
            node.set_status(Status::MARK1)
            r = subexp_inf_recursive_check(node.target, env, true)
            raise Error.new(Err::NEVER_ENDING_RECURSION) if r > 0

            node.clear_status(Status::MARK1)
          end
          subexp_inf_recursive_check_trav(node.target, env)
        end
      end

      def subexp_recursive_check(node)
        r = 0
        case node.ntype
        when Node::LIST, Node::ALT
          n = node
          until n.nil?
            r |= subexp_recursive_check(n.car)
            n = n.cdr
          end
        when Node::QTFR
          r = subexp_recursive_check(node.target)
        when Node::ANCHOR
          r = subexp_recursive_check(node.target) if LOOKAROUNDS.include?(node.type)
        when Node::CALL
          r = subexp_recursive_check(node.target)
          node.set_status(Status::RECURSION) if r != 0
        when Node::ENCLOSE
          if node.status?(Status::MARK2)
            return 0
          elsif node.status?(Status::MARK1)
            return 1 # recursion
          else
            node.set_status(Status::MARK2)
            begin
              r = subexp_recursive_check(node.target)
            ensure
              node.clear_status(Status::MARK2)
            end
          end
        end
        r
      end

      def subexp_recursive_check_trav(node, env)
        r = 0
        case node.ntype
        when Node::LIST, Node::ALT
          n = node
          until n.nil?
            ret = subexp_recursive_check_trav(n.car, env)
            r = FOUND_CALLED_NODE if ret == FOUND_CALLED_NODE
            n = n.cdr
          end
        when Node::QTFR
          r = subexp_recursive_check_trav(node.target, env)
          node.is_referred = true if node.upper == 0 && r == FOUND_CALLED_NODE
        when Node::ANCHOR
          r = subexp_recursive_check_trav(node.target, env) if LOOKAROUNDS.include?(node.type)
        when Node::ENCLOSE
          if !node.status?(Status::RECURSION) && node.status?(Status::CALLED)
            node.set_status(Status::MARK1)
            ret = subexp_recursive_check(node.target)
            node.set_status(Status::RECURSION) if ret != 0
            node.clear_status(Status::MARK1)
          end
          r = subexp_recursive_check_trav(node.target, env)
          r |= FOUND_CALLED_NODE if node.status?(Status::CALLED)
        end
        r
      end

      def setup_subexp_call(node, env)
        case node.ntype
        when Node::LIST, Node::ALT
          n = node
          until n.nil?
            setup_subexp_call(n.car, env)
            n = n.cdr
          end
        when Node::QTFR then setup_subexp_call(node.target, env)
        when Node::ENCLOSE then setup_subexp_call(node.target, env)
        when Node::CALL
          if node.group_num != 0
            gnum = node.group_num
            if env.num_named > 0 && Syntax.bv?(Syntax::CAPTURE_ONLY_NAMED_GROUP) && (env.option & Option::CAPTURE_GROUP) == 0
              raise Error.new(Err::NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED)
            end
            raise Error.new(Err::UNDEFINED_GROUP_REFERENCE, node.name, env.enc) if gnum > env.num_mem
          elsif node.name.bytesize == 0
            nil # (?R), (?0), \g<0>
          else
            refs = env.reg.name_to_group_numbers(node.name)
            raise Error.new(Err::UNDEFINED_NAME_REFERENCE, node.name, env.enc) if refs.nil? || refs.empty?
            if refs.size > 1 && !Syntax.bv?(Syntax::ALLOW_MULTIPLEX_DEFINITION_NAME_CALL)
              raise Error.new(Err::MULTIPLEX_DEFINITION_NAME_CALL, node.name, env.enc)
            end

            node.group_num = refs[0]
          end
          # set_call_attr:
          node.target = env.mem_nodes[node.group_num]
          raise Error.new(Err::UNDEFINED_NAME_REFERENCE, node.name, env.enc) if node.target.nil?

          node.target.set_status(Status::CALLED)
          env.bt_mem_start = Onig.bit_status_on_at(env.bt_mem_start, node.group_num)
          node.unset_addr_list = env.unset_addr_list
        when Node::ANCHOR
          setup_subexp_call(node.target, env) if LOOKAROUNDS.include?(node.type)
        end
      end

      # ---- look-behind ----

      # divide_look_behind_alternatives: (?<=A|B) ==> (?<=A)|(?<=B),
      # (?<!A|B) ==> (?<!A)(?<!B), in place.
      def divide_look_behind_alternatives(node)
        anc_type = node.type
        head = node.target
        np = head.car
        node.swap!(head)
        node.car = head
        head.target = np

        np = node
        until (np = np.cdr).nil?
          insert_node = Node.anchor(anc_type)
          insert_node.target = np.car
          np.car = insert_node
        end

        if anc_type == Anchor::LOOK_BEHIND_NOT
          np = node
          until np.nil?
            np.ntype = Node::LIST # alt -> list
            np = np.cdr
          end
        end
      end

      def setup_look_behind(node, reg)
        r, len = char_length_tree1(node.target, reg, 0)
        if r == 0
          node.char_len = len
        elsif r == GET_CHAR_LEN_VARLEN
          raise Error.new(Err::INVALID_LOOK_BEHIND_PATTERN)
        elsif r == GET_CHAR_LEN_TOP_ALT_VARLEN
          raise Error.new(Err::INVALID_LOOK_BEHIND_PATTERN) unless Syntax.bv?(Syntax::DIFFERENT_LEN_ALT_LOOK_BEHIND)

          divide_look_behind_alternatives(node)
        end
      end

      # next_setup: what a greedy endless quantifier knows about what
      # follows it, and a*b ==> (?>a*)b when a cannot start b.
      def next_setup(node, next_node, reg)
        loop do
          if node.ntype == Node::QTFR
            qn = node
            if qn.greedy && qn.upper == REPEAT_INFINITE
              n = head_value_node(next_node, true, reg)
              qn.next_head_exact = n if !n.nil? && n.s.getbyte(0) != 0 # '\0': for UTF-16BE etc...

              # automatic possessification a*b ==> (?>a*)b
              if qn.lower <= 1 && qn.target.simple?
                x = head_value_node(qn.target, false, reg)
                unless x.nil?
                  y = head_value_node(next_node, false, reg)
                  if !y.nil? && not_included?(x, y, reg)
                    en = Node.enclose(Enclose::STOP_BACKTRACK)
                    en.set_status(Status::STOP_BT_SIMPLE_REPEAT)
                    node.swap!(en)
                    node.target = en
                  end
                end
              end
            end
            return
          elsif node.ntype == Node::ENCLOSE && node.type == Enclose::MEMORY && !node.status?(Status::CALLED)
            node = node.target
          else
            return
          end
        end
      end

      # ---- case fold expansion of strings ----

      # update_string_node_case_fold: the node's bytes folded.
      def update_string_node_case_fold(reg, node)
        s = node.s
        e = s.bytesize
        out = "".b
        p = 0
        while p < e
          folded, len = reg.enc.mbc_case_fold(reg.case_fold_flag, s, p, e)
          out << folded
          p += len
        end
        node.str_set(out)
      end

      def expand_case_fold_make_rem_string(s, reg)
        node = Node.str(s)
        update_string_node_case_fold(reg, node)
        node.flag |= StrFlag::AMBIG | StrFlag::DONT_GET_OPT_INFO
        node
      end

      def case_fold_variable_len?(items, slen)
        items.any? { |byte_len, codes| byte_len != slen || codes.size != 1 }
      end

      # expand_case_fold_string_alt: [varlen (0 or 1), the alternation node]
      def expand_case_fold_string_alt(items, s, p, slen, e, reg)
        varlen = items.any? { |byte_len, _| byte_len != slen }
        var_anode = nil
        if varlen
          rnode = var_anode = Node.alt(nil, nil)
          xnode = Node.list(nil, nil)
          var_anode.car = xnode
          anode = Node.alt(nil, nil)
          xnode.car = anode
        else
          rnode = anode = Node.alt(nil, nil)
        end

        anode.car = Node.str(s.byteslice(p, slen))

        items.each do |byte_len, codes|
          snode = Node.str("".b)
          codes.each { |code| snode.str_cat(reg.enc.code_to_mbc(code)) }
          an = Node.alt(nil, nil)
          if byte_len != slen
            q = p + byte_len
            if q < e
              rem = expand_case_fold_make_rem_string(s.byteslice(q, e - q), reg)
              xnode = Node.list(snode, nil)
              Node.list_add(xnode, rem)
              an.car = xnode
            else
              an.car = snode
            end
            var_anode.cdr = an
            var_anode = an
          else
            an.car = snode
            anode.cdr = an
            anode = an
          end
        end
        [varlen ? 1 : 0, rnode]
      end

      # expand_case_fold_string: a string under /i as the alternatives
      # its case folds make, in place.
      def expand_case_fold_string(node, reg, state)
        return if node.str_ambig?

        s = node.s
        e = s.bytesize
        return if e <= 0

        is_in_look_behind = (state & IN_LOOK_BEHIND) != 0
        top_root = root = prev_node = snode = nil
        alt_num = 1
        p = 0
        while p < e
          items = reg.enc.case_fold_codes_by_str(reg.case_fold_flag, s, p, e)
          len = reg.enc.enclen(s, p, e)
          varlen = case_fold_variable_len?(items, len)
          if items.empty? || !varlen || is_in_look_behind
            if snode.nil?
              if root.nil? && !prev_node.nil?
                top_root = root = Node.list_add(nil, prev_node)
              end
              prev_node = snode = Node.str("".b)
              Node.list_add(root, snode) unless root.nil?
            end
            snode.str_cat(s.byteslice(p, len))
          else
            alt_num *= (items.size + 1)
            break if alt_num > THRESHOLD_CASE_FOLD_ALT_FOR_EXPANSION

            unless snode.nil?
              update_string_node_case_fold(reg, snode)
              snode.flag |= StrFlag::AMBIG
            end
            if root.nil? && !prev_node.nil?
              top_root = root = Node.list_add(nil, prev_node)
            end

            r, prev_node = expand_case_fold_string_alt(items, s, p, len, e, reg)
            if r == 1
              if root.nil?
                top_root = prev_node
              else
                Node.list_add(root, prev_node)
              end
              root = prev_node.car
            elsif !root.nil?
              Node.list_add(root, prev_node)
            end
            snode = nil
          end
          p += len
        end

        unless snode.nil?
          update_string_node_case_fold(reg, snode)
          snode.flag |= StrFlag::AMBIG
        end

        if p < e
          srem = expand_case_fold_make_rem_string(s.byteslice(p, e - p), reg)
          if !prev_node.nil? && root.nil?
            top_root = root = Node.list_add(nil, prev_node)
          end
          if root.nil?
            prev_node = srem
          else
            Node.list_add(root, srem)
          end
        end

        # ending
        top_root = top_root.nil? ? prev_node : top_root
        node.swap!(top_root)
      end

      # ---- setup_tree ----

      ALLOWED_TYPE_IN_LB = [Node::LIST, Node::ALT, Node::STR, Node::CCLASS, Node::CTYPE, Node::CANY,
                            Node::ANCHOR, Node::ENCLOSE, Node::QTFR, Node::CALL].sum { |t| 1 << t }
      ALLOWED_ENCLOSE_IN_LB = Enclose::MEMORY | Enclose::OPTION
      ALLOWED_ENCLOSE_IN_LB_NOT = Enclose::OPTION
      ALLOWED_ANCHOR_IN_LB = Anchor::LOOK_BEHIND | Anchor::LOOK_BEHIND_NOT | Anchor::BEGIN_LINE |
                             Anchor::END_LINE | Anchor::BEGIN_BUF | Anchor::BEGIN_POSITION | Anchor::KEEP |
                             Anchor::WORD_BOUND | Anchor::NOT_WORD_BOUND | Anchor::WORD_BEGIN | Anchor::WORD_END
      ALLOWED_ANCHOR_IN_LB_NOT = ALLOWED_ANCHOR_IN_LB

      # setup_tree: empty loops, case folds, memory status bits, the
      # look-behind checks, repeated strings expanded.
      def setup_tree(node, reg, state, env)
        loop do
          case node.ntype
          when Node::LIST
            prev = nil
            n = node
            until n.nil?
              setup_tree(n.car, reg, state, env)
              next_setup(prev, n.car, reg) unless prev.nil?
              prev = n.car
              n = n.cdr
            end
          when Node::ALT
            n = node
            until n.nil?
              setup_tree(n.car, reg, state | IN_ALT, env)
              n = n.cdr
            end
          when Node::STR
            expand_case_fold_string(node, reg, state) if (reg.options & Option::IGNORECASE) != 0 && !node.str_raw?
          when Node::BREF
            node.backs.each do |b|
              raise Error.new(Err::INVALID_BACKREF) if b > env.num_mem

              env.backrefed_mem = Onig.bit_status_on_at(env.backrefed_mem, b)
              env.bt_mem_start = Onig.bit_status_on_at(env.bt_mem_start, b)
              env.bt_mem_end = Onig.bit_status_on_at(env.bt_mem_end, b) if node.status?(Status::NEST_LEVEL)
              env.mem_nodes[b].set_status(Status::MEM_BACKREFED)
            end
          when Node::QTFR
            qn = node
            target = qn.target
            qn.set_status(Status::IN_REPEAT) if (state & IN_REPEAT) != 0

            if qn.upper == REPEAT_INFINITE || qn.upper >= 1
              d = min_match_length(target, env)
              if d == 0
                qn.target_empty_info = TargetEmpty::IS_EMPTY
                r = quantifiers_memory_node_info(target)
                qn.target_empty_info = r if r > 0
              end
            end

            state |= IN_REPEAT
            state |= IN_VAR_REPEAT if qn.lower != qn.upper
            setup_tree(target, reg, state, env)

            # expand string
            if target.ntype == Node::STR && qn.lower > 1
              n = qn.lower
              len = target.s.bytesize
              np = Node.str(target.s)
              np.flag = target.flag
              i = 1
              while i < n && (i + 1) * len <= EXPAND_STRING_MAX_LENGTH
                np.str_cat(target.s)
                i += 1
              end
              if i < qn.upper || qn.upper == REPEAT_INFINITE
                qn.lower -= i
                qn.upper -= i if qn.upper != REPEAT_INFINITE
                np1 = Node.list(np, nil)
                np1.swap!(node)
                Node.list_add(node, np1)
              else
                np.swap!(node)
              end
            end
          when Node::ENCLOSE
            en = node
            case en.type
            when Enclose::OPTION
              options = reg.options
              reg.options = en.option
              setup_tree(en.target, reg, state, env)
              reg.options = options
            when Enclose::MEMORY
              if (state & (IN_ALT | IN_NOT | IN_VAR_REPEAT | IN_CALL)) != 0
                env.bt_mem_start = Onig.bit_status_on_at(env.bt_mem_start, en.regnum)
              end
              state |= IN_CALL if en.status?(Status::CALLED)
              if en.status?(Status::RECURSION)
                state |= IN_RECCALL
              elsif (state & IN_RECCALL) != 0
                en.set_status(Status::RECURSION)
              end
              setup_tree(en.target, reg, state, env)
            when Enclose::STOP_BACKTRACK
              target = en.target
              setup_tree(target, reg, state, env)
              if target.ntype == Node::QTFR
                tqn = target
                if tqn.upper == REPEAT_INFINITE && tqn.lower <= 1 && tqn.greedy && tqn.target.simple?
                  en.set_status(Status::STOP_BT_SIMPLE_REPEAT) # (?>a*), a*+ etc...
                end
              end
            when Enclose::CONDITION
              if !en.status?(Status::NAME_REF) && env.num_named > 0 && Syntax.bv?(Syntax::CAPTURE_ONLY_NAMED_GROUP) &&
                 (env.option & Option::CAPTURE_GROUP) == 0
                raise Error.new(Err::NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED)
              end
              raise Error.new(Err::INVALID_BACKREF) if en.regnum > env.num_mem

              setup_tree(en.target, reg, state, env)
            when Enclose::ABSENT
              setup_tree(en.target, reg, state, env)
            end
          when Node::ANCHOR
            an = node
            case an.type
            when Anchor::PREC_READ
              setup_tree(an.target, reg, state, env)
            when Anchor::PREC_READ_NOT
              setup_tree(an.target, reg, state | IN_NOT, env)
            when Anchor::LOOK_BEHIND
              raise Error.new(Err::INVALID_LOOK_BEHIND_PATTERN) if check_type_tree(an.target, ALLOWED_TYPE_IN_LB, ALLOWED_ENCLOSE_IN_LB, ALLOWED_ANCHOR_IN_LB)
              next if node.ntype != Node::ANCHOR # restart

              setup_tree(an.target, reg, state | IN_LOOK_BEHIND, env)
              setup_look_behind(node, reg)
            when Anchor::LOOK_BEHIND_NOT
              raise Error.new(Err::INVALID_LOOK_BEHIND_PATTERN) if check_type_tree(an.target, ALLOWED_TYPE_IN_LB, ALLOWED_ENCLOSE_IN_LB_NOT, ALLOWED_ANCHOR_IN_LB_NOT)
              next if node.ntype != Node::ANCHOR # restart

              setup_tree(an.target, reg, state | IN_NOT | IN_LOOK_BEHIND, env)
              setup_look_behind(node, reg)
            end
          end
          return
        end
      end
    end
  end
end
