# frozen_string_literal: true

require_relative "types"

module Zr
  module IR
    # Makes a jump table (`switch`) of a tree of branches that each
    # compare one value with a constant: the kernel's opcode dispatch (the
    # regexp VM's `zr_onig_step` and its handlers), and a chain of `==`.
    #
    # The tree starts at a block that ends in a `brif` on such a compare.
    # A target is a node of the tree when it does nothing else (a compare
    # and its `brif`) and has no other predecessor. Every other target is
    # a leaf. The pass runs each value of the table's range through the
    # tree to find its leaf. A value outside the range goes to the
    # default, so each value outside must reach one leaf: the pass checks
    # one value below the range, one above it, and one negative. A value
    # that is a widened byte has no value outside 0..255, so its table can
    # cover all 256.
    class Switches
      MASK = { "i8" => 0xFF, "i32" => 0xFFFF_FFFF, "i64" => 0xFFFF_FFFF_FFFF_FFFF }.freeze
      SWAPPED = { "eq" => "eq", "ne" => "ne", "slt" => "sgt", "sle" => "sge", "sgt" => "slt", "sge" => "sle",
                  "ult" => "ugt", "ule" => "uge", "ugt" => "ult", "uge" => "ule" }.freeze
      # The fewest compares that a table replaces.
      FEWEST = 4
      # The most nodes of one tree.
      MOST = 64

      def self.run(f) = new(f).run

      def initialize(f)
        @f = f
        @const = {}
        @def = {}
        @f.blocks.each do |b|
          b.insts.each do |i|
            @const[i.results[0]] = i.args[0] if i.op == :iconst
            i.results.each { |r| @def[r] = i }
          end
        end
        @named = @f.blocks.to_h { |b| [b.name, b] }
        @uses = @f.analysis.uses
        @preds = @f.analysis.preds
        @types = nil
      end

      def run
        changed = false
        # A node of one tree is not the root of another: each tree is found
        # before any table changes a block.
        trees = @f.blocks.filter_map { |b| (test = test_of(b, nil)) && [b, test, collect(b, test[0], {})] }
        inner = trees.flat_map { |b, _, nodes| nodes.keys - [b.name] }.to_set
        trees.each do |b, test, nodes|
          changed = true if !inner.include?(b.name) && tabled?(b, test, nodes)
        end
        @f.changed!(:cfg) if changed
        @f
      end

      private

      # `[value, cond, constant]` when `b` ends in a `brif` on a compare of
      # `value` (or any value when `value` is nil) with a constant, and the
      # branch alone reads the compare.
      def test_of(b, value)
        br = b.insts.last
        return unless br&.op == :brif && @uses[br.args[0]] == 1

        cmp = @def[br.args[0]]
        return unless cmp&.op == :icmp && b.insts.include?(cmp)

        x, y = cmp.args
        cond = cmp.cond
        x, y, cond = y, x, SWAPPED.fetch(cond) if @const.key?(x)
        return unless @const.key?(y) && !@const.key?(x) && IR.value?(x)
        return if value && x != value

        [x, cond, @const[y]]
      end

      # Makes the table of the tree `nodes` under `b`, if it pays.
      def tabled?(b, (value, *), nodes)
        return false if nodes.size < FEWEST

        @types ||= Types.of(@f)
        type = @types[value]
        return false unless MASK.key?(type)

        keys = nodes.each_value.map { |(_, k, _, _)| k & MASK.fetch(type) }
        cases, default = cases_of(b.name, nodes, keys, value, type)
        return false unless cases

        b.insts[-1] = Inst.new(:switch, args: [value, *cases.keys.sort],
                                        targets: [[default, []], *cases.keys.sort.map { |k| [cases.fetch(k), []] }])
        true
      end

      # Returns `nodes`: `{ name => [cond, constant, yes, no] }` for `b`
      # and each node under it.
      def collect(b, value, nodes)
        return nodes if nodes.size >= MOST

        _, cond, k = test_of(b, value)
        yes, no = b.insts.last.targets.map { |(t, _)| through(t) }
        nodes[b.name] = [cond, k, yes, no]
        [yes, no].each do |t|
          c = @named.fetch(t)
          next if nodes.key?(t) || c.insts.size != 2 || @preds[t].size != 1 || !test_of(c, value)

          collect(c, value, nodes)
        end
        nodes
      end

      # The block that `name` leads to past blocks that only jump on with
      # no arguments (`Blocks` would skip them later).
      def through(name)
        8.times do
          b = @named.fetch(name)
          i = b.insts[0]
          break unless b.params.empty? && b.insts.size == 1 && i.op == :jump && i.targets[0][1].empty?

          name = i.targets[0][0]
        end
        name
      end

      # The table: `{ key => leaf }` and the default leaf, or nil when the
      # table is too large or a value outside it has no one leaf.
      def cases_of(root, nodes, keys, value, type)
        lo, hi = keys.minmax
        top = byte?(value) ? 255 : MASK.fetch(type) >> 1
        outside = [hi < top ? hi + 1 : nil, lo.positive? ? lo - 1 : nil]
        # A byte is never negative. A word can be, and a negative value is
        # a third region: above the range unsigned, below it signed.
        outside << MASK.fetch(type) unless top == 255
        # Below the range is one more region. When it has another leaf, a
        # byte's table starts at 0, so nothing is below it.
        if top == 255 && outside.compact.map { |x| leaf(root, nodes, x, type) }.uniq.size > 1
          lo = 0
          outside[1] = nil
        end
        leaves = outside.compact.map { |x| leaf(root, nodes, x, type) }.uniq
        return if leaves.size > 1 || hi - lo + 1 > [64, 32 * nodes.size].max

        default = leaves[0] || leaf(root, nodes, lo, type)
        cases = {}
        (lo..hi).each do |x|
          to = leaf(root, nodes, x, type)
          cases[x] = to unless to == default
        end
        [cases, default]
      end

      # Whether `value` is a byte widened to a word: it has no value
      # outside 0..255.
      def byte?(value)
        i = @def[value]
        @types[value] == "i8" || (i&.op == :uextend && @types[i.args[0]] == "i8")
      end

      # The leaf that `x` reaches from `root`.
      def leaf(root, nodes, x, type)
        name = root
        while (node = nodes[name])
          cond, k, yes, no = node
          name = holds?(cond, x, k & MASK.fetch(type), type) ? yes : no
        end
        name
      end

      def holds?(cond, a, b, type)
        bits = type == "i64" ? 64 : 32
        a, b = signed(a, bits), signed(b, bits) if cond.start_with?("s")
        case cond
        when "eq" then a == b
        when "ne" then a != b
        when "slt", "ult" then a < b
        when "sle", "ule" then a <= b
        when "sgt", "ugt" then a > b
        when "sge", "uge" then a >= b
        end
      end

      def signed(raw, bits)
        raw &= (1 << bits) - 1
        top = 1 << (bits - 1)
        raw >= top ? raw - (top << 1) : raw
      end
    end
  end
end
