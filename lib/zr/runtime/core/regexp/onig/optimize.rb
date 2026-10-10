# frozen_string_literal: true

# Onigmo's search optimizer: what a pattern's tree says about where a
# match can start (regcomp.c:4220-5400), written onto the regex as its
# optimize kind, anchors, exact string or map, and distances. A port
# under the BSD-2-Clause license reproduced in regexp.rb.
class Regexp
  module Onig
    module Optimize
      OPTIMIZE_NONE = 0
      OPTIMIZE_EXACT = 1
      OPTIMIZE_EXACT_BM = 2
      OPTIMIZE_EXACT_BM_NOT_REV = 3
      OPTIMIZE_EXACT_IC = 4
      OPTIMIZE_MAP = 5
      OPTIMIZE_EXACT_BM_IC = 6
      OPTIMIZE_EXACT_BM_NOT_REV_IC = 7

      MAX_NODE_OPT_INFO_REF_COUNT = 5
      COMP_EM_BASE = 20

      BYTE_VAL_TABLE = [
        5, 1, 1, 1, 1, 1, 1, 1, 1, 10, 10, 1, 1, 10, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        12, 4, 7, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5,
        6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5, 5, 5,
        5, 6, 6, 6, 6, 7, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
        6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 6, 5, 5, 5,
        5, 6, 6, 6, 6, 7, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
        6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5, 1
      ].freeze

      DIST_VALS = [
        1000, 500, 333, 250, 200, 167, 143, 125, 111, 100,
        91, 83, 77, 71, 67, 63, 59, 56, 53, 50,
        48, 45, 43, 42, 40, 38, 37, 36, 34, 33,
        32, 31, 30, 29, 29, 28, 27, 26, 26, 25,
        24, 24, 23, 23, 22, 22, 21, 21, 20, 20,
        20, 19, 19, 19, 18, 18, 18, 17, 17, 17,
        16, 16, 16, 16, 15, 15, 15, 15, 14, 14,
        14, 14, 14, 14, 13, 13, 13, 13, 13, 13,
        12, 12, 12, 12, 12, 12, 11, 11, 11, 11,
        11, 11, 11, 11, 11, 10, 10, 10, 10, 10
      ].freeze

      # MinMaxLen
      class MinMax
        attr_accessor :min, :max

        def initialize(min = 0, max = 0)
          @min = min
          @max = max
        end

        def copy = MinMax.new(@min, @max)
        def set(min, max) = (@min = min; @max = max)
        def clear = set(0, 0)
        def copy_from(other) = set(other.min, other.max)
        def ==(other) = @min == other.min && @max == other.max

        def add(other)
          @min = Onig.distance_add(@min, other.min)
          @max = Onig.distance_add(@max, other.max)
        end

        def alt_merge(other)
          @min = other.min if @min > other.min
          @max = other.max if @max < other.max
        end
      end

      # OptAncInfo
      class AncInfo
        attr_accessor :left, :right

        def initialize(left = 0, right = 0)
          @left = left
          @right = right
        end

        def copy = AncInfo.new(@left, @right)
        def clear = (@left = 0; @right = 0)
        def copy_from(other) = (@left = other.left; @right = other.right)

        # concat_opt_anc_info
        def self.concat(left, right, left_len, right_len)
          to = AncInfo.new
          to.left = left.left
          to.left |= right.left if left_len == 0
          to.right = right.right
          if right_len == 0
            to.right |= left.right
          else
            to.right |= (left.right & Anchor::PREC_READ_NOT)
          end
          to
        end

        def self.left_anchor?(anc)
          !(anc == Anchor::END_BUF || anc == Anchor::SEMI_END_BUF || anc == Anchor::END_LINE ||
            anc == Anchor::PREC_READ || anc == Anchor::PREC_READ_NOT)
        end

        def set?(anc) = (@left & anc) != 0 || (@right & anc) != 0

        def add(anc)
          if AncInfo.left_anchor?(anc)
            @left |= anc
          else
            @right |= anc
          end
        end

        def remove(anc)
          if AncInfo.left_anchor?(anc)
            @left &= ~anc
          else
            @right &= ~anc
          end
        end

        def alt_merge(other)
          @left &= other.left
          @right &= other.right
        end
      end

      # OptExactInfo
      class ExactInfo
        attr_accessor :mmd, :anc, :reach_end, :ignore_case, :s

        def initialize
          @mmd = MinMax.new
          @anc = AncInfo.new
          @reach_end = false
          @ignore_case = -1 # unset
          @s = "".b
        end

        def len = @s.bytesize
        def full? = len >= OPT_EXACT_MAXLEN

        def clear
          @mmd.clear
          @anc.clear
          @reach_end = false
          @ignore_case = -1
          @s = "".b
        end

        def copy
          to = ExactInfo.new
          to.copy_from(self)
          to
        end

        def copy_from(other)
          @mmd = other.mmd.copy
          @anc = other.anc.copy
          @reach_end = other.reach_end
          @ignore_case = other.ignore_case
          @s = other.s.dup
        end

        # concat_opt_exact_info
        def concat(add, enc)
          if @ignore_case < 0
            @ignore_case = add.ignore_case
          elsif @ignore_case != add.ignore_case
            return # avoid
          end

          p = 0
          e = add.len
          i = len
          while p < e
            l = enc.enclen(add.s, p, e)
            break if i + l > OPT_EXACT_MAXLEN

            @s << add.s.byteslice(p, l)
            i += l
            p += l
          end
          @reach_end = p == e ? add.reach_end : false

          tanc = AncInfo.concat(@anc, add.anc, 1, 1)
          tanc.right = 0 unless @reach_end
          @anc = tanc
        end

        # concat_opt_exact_info_str
        def concat_str(s, enc)
          p = 0
          e = s.bytesize
          i = len
          while p < e && i < OPT_EXACT_MAXLEN
            l = enc.enclen(s, p, e)
            break if i + l > OPT_EXACT_MAXLEN

            @s << s.byteslice(p, l)
            i += l
            p += l
          end
        end

        # alt_merge_opt_exact_info
        def alt_merge(add, enc)
          if add.len == 0 || len == 0 || @mmd != add.mmd
            clear
            return
          end

          i = 0
          while i < len && i < add.len
            break if @s.getbyte(i) != add.s.getbyte(i)

            l = enc.enclen(@s, i, len)
            j = 1
            while j < l
              break if @s.getbyte(i + j) != add.s.getbyte(i + j)

              j += 1
            end
            break if j < l

            i += l
          end

          @reach_end = false if !add.reach_end || i < add.len || i < len
          @s = @s.byteslice(0, i)
          if @ignore_case < 0
            @ignore_case = add.ignore_case
          elsif add.ignore_case >= 0
            @ignore_case |= add.ignore_case
          end

          @anc.alt_merge(add.anc)
          @anc.right = 0 unless @reach_end
        end

        # select_opt_exact_info: `alt` taken over `self` when it is the better one.
        def select(alt, enc)
          v1 = len
          v2 = alt.len
          return if v2 == 0

          if v1 == 0
            copy_from(alt)
            return
          elsif v1 <= 2 && v2 <= 2
            # ByteValTable[x] is big value --> low price
            v2 = Optimize.map_position_value(enc, @s.getbyte(0))
            v1 = Optimize.map_position_value(enc, alt.s.getbyte(0))
            v1 += 5 if len > 1
            v2 += 5 if alt.len > 1
          end

          v1 *= 2 if @ignore_case <= 0
          v2 *= 2 if alt.ignore_case <= 0
          copy_from(alt) if Optimize.comp_distance_value(@mmd, alt.mmd, v1, v2) > 0
        end
      end

      # OptMapInfo
      class MapInfo
        attr_accessor :mmd, :anc, :value, :map

        def initialize
          @mmd = MinMax.new
          @anc = AncInfo.new
          @value = 0
          @map = Array.new(CHAR_TABLE_SIZE, 0)
        end

        def clear
          @mmd.clear
          @anc.clear
          @value = 0
          @map = Array.new(CHAR_TABLE_SIZE, 0)
        end

        def copy
          to = MapInfo.new
          to.copy_from(self)
          to
        end

        def copy_from(other)
          @mmd = other.mmd.copy
          @anc = other.anc.copy
          @value = other.value
          @map = other.map.dup
        end

        # add_char_opt_map_info
        def add_char(c, enc)
          return unless @map[c] == 0

          @map[c] = 1
          @value += Optimize.map_position_value(enc, c)
        end

        # add_char_amb_opt_map_info
        def add_char_amb(s, enc, case_fold_flag)
          add_char(s.getbyte(0), enc)
          case_fold_flag &= ~CASE_FOLD_MULTI_CHAR
          items = enc.case_fold_codes_by_str(case_fold_flag, s, 0, s.bytesize)
          items.each { |_len, codes| add_char(enc.code_to_mbc(codes[0]).getbyte(0), enc) }
        end

        # select_opt_map_info
        def select(alt)
          z = 1 << 15 # 32768: something big value
          return if alt.value == 0

          if @value == 0
            copy_from(alt)
            return
          end

          v1 = z / @value
          v2 = z / alt.value
          copy_from(alt) if Optimize.comp_distance_value(@mmd, alt.mmd, v1, v2) > 0
        end

        # alt_merge_opt_map_info
        def alt_merge(enc, add)
          return if @value == 0

          if add.value == 0 || @mmd.max < add.mmd.min
            clear
            return
          end

          @mmd.alt_merge(add.mmd)
          val = 0
          CHAR_TABLE_SIZE.times do |i|
            @map[i] = 1 if add.map[i] != 0
            val += Optimize.map_position_value(enc, i) if @map[i] != 0
          end
          @value = val
          @anc.alt_merge(add.anc)
        end
      end

      # NodeOptInfo
      class NodeInfo
        attr_accessor :len, :anc, :exb, :exm, :expr, :map

        def initialize
          @len = MinMax.new
          @anc = AncInfo.new
          @exb = ExactInfo.new
          @exm = ExactInfo.new
          @expr = ExactInfo.new
          @map = MapInfo.new
        end

        def copy_from(other)
          @len = other.len.copy
          @anc = other.anc.copy
          @exb = other.exb.copy
          @exm = other.exm.copy
          @expr = other.expr.copy
          @map = other.map.copy
        end

        # set_bound_node_opt_info
        def set_bound(mmd)
          @exb.mmd.copy_from(mmd)
          @expr.mmd.copy_from(mmd)
          @map.mmd.copy_from(mmd)
        end

        # concat_left_node_opt_info
        def concat_left(enc, add)
          @anc = AncInfo.concat(@anc, add.anc, @len.max, add.len.max)

          if add.exb.len > 0 && @len.max == 0
            add.exb.anc = AncInfo.concat(@anc, add.exb.anc, @len.max, add.len.max)
          end

          if add.map.value > 0 && @len.max == 0 && add.map.mmd.max == 0
            add.map.anc.left |= @anc.left
          end

          exb_reach = @exb.reach_end
          exm_reach = @exm.reach_end
          if add.len.max != 0
            @exb.reach_end = false
            @exm.reach_end = false
          end

          if add.exb.len > 0
            if exb_reach
              @exb.concat(add.exb, enc)
              add.exb.clear
            elsif exm_reach
              @exm.concat(add.exb, enc)
              add.exb.clear
            end
          end
          @exm.select(add.exb, enc)
          @exm.select(add.exm, enc)

          if @expr.len > 0
            if add.len.max > 0
              @expr.s = @expr.s.byteslice(0, add.len.max) if @expr.len > add.len.max
              if @expr.mmd.max == 0
                @exb.select(@expr, enc)
              else
                @exm.select(@expr, enc)
              end
            end
          elsif add.expr.len > 0
            @expr.copy_from(add.expr)
          end

          @map.select(add.map)
          @len.add(add.len)
        end

        # alt_merge_node_opt_info
        def alt_merge(add, enc)
          @anc.alt_merge(add.anc)
          @exb.alt_merge(add.exb, enc)
          @exm.alt_merge(add.exm, enc)
          @expr.alt_merge(add.expr, enc)
          @map.alt_merge(enc, add.map)
          @len.alt_merge(add.len)
        end
      end

      # OptEnv
      class Env
        attr_accessor :mmd, :enc, :options, :case_fold_flag, :scan_env

        def initialize(enc, options, case_fold_flag, scan_env)
          @mmd = MinMax.new
          @enc = enc
          @options = options
          @case_fold_flag = case_fold_flag
          @scan_env = scan_env
        end

        def copy
          e = Env.new(@enc, @options, @case_fold_flag, @scan_env)
          e.mmd = @mmd.copy
          e
        end
      end

      module_function

      def map_position_value(enc, i)
        if i < BYTE_VAL_TABLE.size
          i == 0 && enc.min_len > 1 ? 20 : BYTE_VAL_TABLE[i]
        else
          4 # Take it easy.
        end
      end

      def distance_value(mm)
        return 0 if mm.max == INFINITE_DISTANCE

        d = mm.max - mm.min
        d < DIST_VALS.size ? DIST_VALS[d] : 1
      end

      def comp_distance_value(d1, d2, v1, v2)
        return -1 if v2 <= 0
        return 1 if v1 <= 0

        v1 *= distance_value(d1)
        v2 *= distance_value(d2)
        return 1 if v2 > v1
        return -1 if v2 < v1
        return 1 if d2.min < d1.min
        return -1 if d2.min > d1.min

        0
      end

      # comp_opt_exact_or_map_info
      def comp_exact_or_map(e, m)
        return -1 if m.value <= 0

        ve = COMP_EM_BASE * e.len * (e.ignore_case > 0 ? 1 : 2)
        vm = COMP_EM_BASE * 5 * 2 / m.value
        comp_distance_value(e.mmd, m.mmd, ve, vm)
      end

      # set_bm_skip: the skip table of Sunday's quick search; [len, skip].
      def set_bm_skip(s, reg, ignore_case)
        enc = reg.enc
        e = s.bytesize
        len = e
        raise Error.new(Err::TYPE_BUG) if len >= CHAR_TABLE_SIZE

        if ignore_case
          i = 0
          stop = false
          while i < len && !stop
            items = enc.case_fold_codes_by_str(reg.case_fold_flag, s, i, e)
            clen = enc.enclen(s, i, e)
            clen = e - i if i + clen > e
            items.each do |byte_len, codes|
              if codes.size != 1 || byte_len != clen
                # Different length isn't supported. Stop optimization at here.
                e = i
                stop = true
                break
              end
              if enc.code_to_mbc(codes[0]).bytesize != clen
                e = i
                stop = true
                break
              end
            end
            i += clen
          end
          len = e
        end

        skip = Array.new(CHAR_TABLE_SIZE, (len + 1) & 0xff)
        items = []
        i = 0
        while i < len
          items = enc.case_fold_codes_by_str(reg.case_fold_flag, s, i, e) if ignore_case
          clen = enc.enclen(s, i, e)
          clen = e - i if i + clen > e
          clen.times do |j|
            skip[s.getbyte(i + j)] = (len - i - j) & 0xff
            items.each do |_byte_len, codes|
              buf = enc.code_to_mbc(codes[0])
              skip[buf.getbyte(j)] = (len - i - j) & 0xff
            end
          end
          i += clen
        end
        [len, skip]
      end

      # optimize_node_left: the optimize info of `node`.
      def node_left(node, env)
        opt = NodeInfo.new
        opt.set_bound(env.mmd)

        case node.ntype
        when Node::LIST
          nenv = env.copy
          n = node
          until n.nil?
            nopt = node_left(n.car, nenv)
            nenv.mmd.add(nopt.len)
            opt.concat_left(env.enc, nopt)
            n = n.cdr
          end
        when Node::ALT
          n = node
          until n.nil?
            nopt = node_left(n.car, env)
            if n.equal?(node)
              opt.copy_from(nopt)
            else
              opt.alt_merge(nopt, env.enc)
            end
            n = n.cdr
          end
        when Node::STR
          s = node.s
          slen = s.bytesize
          if !node.str_ambig?
            opt.exb.concat_str(s, env.enc)
            opt.exb.ignore_case = 0
            opt.map.add_char(s.getbyte(0), env.enc) if slen > 0
            opt.len.set(slen, slen)
          else
            if node.str_dont_get_opt_info?
              n = env.enc.strlen(s, 0, slen)
              max = env.enc.max_len * n
            else
              opt.exb.concat_str(s, env.enc)
              opt.exb.ignore_case = 1
              opt.map.add_char_amb(s, env.enc, env.case_fold_flag) if slen > 0
              max = slen
            end
            opt.len.set(slen, max)
          end
          opt.exb.reach_end = true if opt.exb.len == slen
        when Node::CCLASS
          cc = node
          # no need to check ignore case. (set in setup_tree())
          if !cc.mbuf.nil? || cc.cclass_not?
            opt.len.set(env.enc.min_len, env.enc.max_len)
          else
            256.times do |i|
              z = BitSet.at?(cc.bs, i)
              opt.map.add_char(i, env.enc) if (z && !cc.cclass_not?) || (!z && cc.cclass_not?)
            end
            opt.len.set(1, 1)
          end
        when Node::CTYPE
          max = env.enc.max_len
          if max == 1
            min = 1
            maxcode = node.ascii_range ? 0x80 : 256
            if node.ctype == CType::WORD
              if node.not
                256.times do |i|
                  opt.map.add_char(i, env.enc) if !env.enc.code_ctype?(i, CType::WORD) || i >= maxcode
                end
              else
                maxcode.times do |i|
                  opt.map.add_char(i, env.enc) if env.enc.code_ctype?(i, CType::WORD)
                end
              end
            end
          else
            min = env.enc.min_len
          end
          opt.len.set(min, max)
        when Node::CANY
          opt.len.set(env.enc.min_len, env.enc.max_len)
        when Node::ANCHOR
          case node.type
          when Anchor::BEGIN_BUF, Anchor::BEGIN_POSITION, Anchor::BEGIN_LINE, Anchor::END_BUF,
               Anchor::SEMI_END_BUF, Anchor::END_LINE, Anchor::LOOK_BEHIND, Anchor::PREC_READ_NOT
            opt.anc.add(node.type)
          when Anchor::PREC_READ
            nopt = node_left(node.target, env)
            if nopt.exb.len > 0
              opt.expr.copy_from(nopt.exb)
            elsif nopt.exm.len > 0
              opt.expr.copy_from(nopt.exm)
            end
            opt.expr.reach_end = false
            opt.map.copy_from(nopt.map) if nopt.map.value > 0
          end
        when Node::BREF
          if node.status?(Status::RECURSION)
            opt.len.set(0, INFINITE_DISTANCE)
          else
            nodes = env.scan_env.mem_nodes
            backs = node.backs
            min = Tune.min_match_length(nodes[backs[0]], env.scan_env)
            max = Tune.max_match_length(nodes[backs[0]], env.scan_env)
            backs.drop(1).each do |b|
              tmin = Tune.min_match_length(nodes[b], env.scan_env)
              tmax = Tune.max_match_length(nodes[b], env.scan_env)
              min = tmin if min > tmin
              max = tmax if max < tmax
            end
            opt.len.set(min, max)
          end
        when Node::CALL
          if node.status?(Status::RECURSION)
            opt.len.set(0, INFINITE_DISTANCE)
          else
            save = env.options
            env.options = node.target.option
            opt = node_left(node.target, env)
            env.options = save
          end
        when Node::QTFR
          qn = node
          nopt = node_left(qn.target, env)

          if qn.lower == 0 && qn.upper == REPEAT_INFINITE
            if env.mmd.max == 0 && qn.target.ntype == Node::CANY && qn.greedy
              # implicit anchor: /.*a/ ==> /\A.*a/
              opt.anc.add((env.options & Option::MULTILINE) != 0 ? Anchor::ANYCHAR_STAR_ML : Anchor::ANYCHAR_STAR)
            end
          elsif qn.lower > 0
            opt.copy_from(nopt)
            if nopt.exb.len > 0 && nopt.exb.reach_end
              i = 2
              while i <= qn.lower && !opt.exb.full?
                opt.exb.concat(nopt.exb, env.enc)
                i += 1
              end
              opt.exb.reach_end = false if i < qn.lower
            end

            if qn.lower != qn.upper
              opt.exb.reach_end = false
              opt.exm.reach_end = false
            end
            opt.exm.reach_end = false if qn.lower > 1
          end

          min = Onig.distance_multiply(nopt.len.min, qn.lower)
          max = if qn.upper == REPEAT_INFINITE
                  nopt.len.max > 0 ? INFINITE_DISTANCE : 0
                else
                  Onig.distance_multiply(nopt.len.max, qn.upper)
                end
          opt.len.set(min, max)
        when Node::ENCLOSE
          en = node
          case en.type
          when Enclose::OPTION
            save = env.options
            env.options = en.option
            opt = node_left(en.target, env)
            env.options = save
          when Enclose::MEMORY
            en.opt_count += 1
            if en.opt_count > MAX_NODE_OPT_INFO_REF_COUNT
              min = 0
              max = INFINITE_DISTANCE
              min = en.min_len if en.status?(Status::MIN_FIXED)
              max = en.max_len if en.status?(Status::MAX_FIXED)
              opt.len.set(min, max)
            else
              opt = node_left(en.target, env)
              if opt.anc.set?(Anchor::ANYCHAR_STAR_MASK) && Onig.bit_status_at?(env.scan_env.backrefed_mem, en.regnum)
                opt.anc.remove(Anchor::ANYCHAR_STAR_MASK)
              end
            end
          when Enclose::STOP_BACKTRACK, Enclose::CONDITION
            opt = node_left(en.target, env)
          when Enclose::ABSENT
            opt.len.set(0, INFINITE_DISTANCE)
          end
        else
          raise Error.new(Err::TYPE_BUG)
        end
        opt
      end

      # set_optimize_exact_info
      def set_exact_info(reg, e)
        return if e.len == 0

        reg.exact = e.s.dup
        allow_reverse = reg.enc.allowed_reverse_match?(reg.exact, 0, reg.exact.bytesize)

        if e.ignore_case > 0
          if e.len >= 3 || (e.len >= 2 && allow_reverse)
            len, skip = set_bm_skip(reg.exact, reg, true)
            if len >= 3
              reg.exact = reg.exact.byteslice(0, len)
              reg.map = skip
              reg.optimize = allow_reverse ? OPTIMIZE_EXACT_BM_IC : OPTIMIZE_EXACT_BM_NOT_REV_IC
            else
              # Even if the BM skip table can't be built (e.g., the pattern
              # starts with 's' or 'k' which have multi-byte case fold
              # variants), EXACT_IC with the whole string still helps.
              # [Bug #21824]
              reg.optimize = OPTIMIZE_EXACT_IC
            end
          else
            reg.optimize = OPTIMIZE_EXACT_IC
          end
        elsif e.len >= 3 || (e.len >= 2 && allow_reverse)
          _, skip = set_bm_skip(reg.exact, reg, false)
          reg.map = skip
          reg.optimize = allow_reverse ? OPTIMIZE_EXACT_BM : OPTIMIZE_EXACT_BM_NOT_REV
        else
          reg.optimize = OPTIMIZE_EXACT
        end

        reg.dmin = e.mmd.min
        reg.dmax = e.mmd.max
        reg.threshold_len = reg.dmin + reg.exact.bytesize if reg.dmin != INFINITE_DISTANCE
      end

      # set_optimize_map_info
      def set_map_info(reg, m)
        reg.map = m.map.dup
        reg.optimize = OPTIMIZE_MAP
        reg.dmin = m.mmd.min
        reg.dmax = m.mmd.max
        reg.threshold_len = reg.dmin + 1 if reg.dmin != INFINITE_DISTANCE
      end

      def set_sub_anchor(reg, anc)
        reg.sub_anchor |= anc.left & Anchor::BEGIN_LINE
        reg.sub_anchor |= anc.right & Anchor::END_LINE
      end

      # clear_optimize_info
      def clear_info(reg)
        reg.optimize = OPTIMIZE_NONE
        reg.anchor = 0
        reg.anchor_dmin = 0
        reg.anchor_dmax = 0
        reg.sub_anchor = 0
        reg.exact = nil
        reg.map = nil
        reg.threshold_len = 0
        reg.dmin = 0
        reg.dmax = 0
      end

      # set_optimize_info_from_tree
      def set_info_from_tree(node, reg, scan_env)
        env = Env.new(reg.enc, reg.options, reg.case_fold_flag, scan_env)
        opt = node_left(node, env)

        reg.anchor = opt.anc.left & (Anchor::BEGIN_BUF | Anchor::BEGIN_POSITION | Anchor::ANYCHAR_STAR |
                                     Anchor::ANYCHAR_STAR_ML | Anchor::LOOK_BEHIND)
        reg.anchor &= ~Anchor::ANYCHAR_STAR_ML if (opt.anc.left & (Anchor::LOOK_BEHIND | Anchor::PREC_READ_NOT)) != 0
        reg.anchor |= opt.anc.right & (Anchor::END_BUF | Anchor::SEMI_END_BUF | Anchor::PREC_READ_NOT)

        if (reg.anchor & (Anchor::END_BUF | Anchor::SEMI_END_BUF)) != 0
          reg.anchor_dmin = opt.len.min
          reg.anchor_dmax = opt.len.max
        end

        if opt.exb.len > 0 || opt.exm.len > 0
          opt.exb.select(opt.exm, reg.enc)
          if opt.map.value > 0 && comp_exact_or_map(opt.exb, opt.map) > 0
            set_map_info(reg, opt.map)
            set_sub_anchor(reg, opt.map.anc)
          else
            set_exact_info(reg, opt.exb)
            set_sub_anchor(reg, opt.exb.anc)
          end
        elsif opt.map.value > 0
          set_map_info(reg, opt.map)
          set_sub_anchor(reg, opt.map.anc)
        else
          reg.sub_anchor |= opt.anc.left & Anchor::BEGIN_LINE
          reg.sub_anchor |= opt.anc.right & Anchor::END_LINE if opt.len.max == 0
        end
      end
    end
  end
end
