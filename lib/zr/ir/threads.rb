# frozen_string_literal: true

module Zr
  module IR
    # Jump threading. An edge that gives a block a constant can skip the
    # blocks that only test that constant. The pass follows the edge
    # through blocks that only jump on (their parameters become the
    # arguments) and blocks that only branch on a compare it can decide,
    # and points the edge at the first block that does more.
    #
    # An inlined kernel def returns a constant to a join, and its caller
    # tests the value at once (`return ONIG_OP_NEXT` and the match loop's
    # `if r == ONIG_OP_FAIL`). Each such return then goes to the right
    # successor with no join and no compare.
    #
    # The new edge must keep each value's definition before its uses. The
    # skipped blocks stay, with their other edges. A skipped block's
    # parameters and results are read only in the blocks that it
    # dominates, so a block that reads one must not be reachable from the
    # new target except through that skipped block.
    class Threads
      # @rbs @f: Function
      # @rbs @const: Hash[String, [Integer, String?]]
      # @rbs @named: Hash[String, Block]
      # @rbs @read_in: Hash[untyped, Set[String]]

      MASK = { "i8" => 0xFF, "i32" => 0xFFFF_FFFF, "i64" => 0xFFFF_FFFF_FFFF_FFFF }.freeze
      SIGNED = %w[slt sle sgt sge].freeze
      # The longest run of blocks that one edge skips.
      LIMIT = 8

      #: (Function f) -> Function
      def self.run(f) = new(f).run

      #: (Function f) -> void
      def initialize(f)
        @f = f
        @const = {}
        @f.blocks.each { |b| b.insts.each { |i| @const[i.results[0]] = [i.args[0] & MASK.fetch(i.type), i.type] if i.op == :iconst } }
        @named = @f.blocks.to_h { |b| [b.name, b] }
        # The blocks that read each value. The pass only moves edges, so
        # this stays a superset.
        @read_in = Hash.new { |h, v| h[v] = Set.new }
        @f.blocks.each do |b|
          b.insts.each do |i|
            i.args.each { |a| @read_in[a] << b.name }
            i.targets&.each { |(_, args)| args.each { |a| @read_in[a] << b.name } }
          end
        end
      end

      #: () -> Function
      def run
        changed = false
        @f.blocks.each do |b|
          t = b.insts.last
          t&.targets&.each_with_index do |(name, args), k|
            to = thread(name, args)
            # Only a `jump` gives its target arguments.
            next unless to && (t.op == :jump || to[1].empty?)

            t.targets[k] = to
            to[1].each { |a| @read_in[a] << b.name }
            changed = true
          end
        end
        @f.changed!(:cfg) if changed
        @f
      end

      private

      # The target and arguments that an edge to `name` with `args` can
      # take in place of its own, or nil.
      #: (String name, Array[String] args) -> [String, Array[String]]?
      def thread(name, args)
        env = {} #: Hash[String, String]
        skipped = [] #: Array[Block]
        args = args.dup
        while skipped.size < LIMIT
          b = @named.fetch(name)
          break if b.equal?(@f.entry_block) || skipped.include?(b)

          bind(b, args, env)
          step = decide(b, env)
          break unless step

          skipped << b
          name, args = step
        end
        return if skipped.empty? || !constant_edge?(skipped)

        args = args.map { |a| env.fetch(a, a) }
        return unless safe?(skipped, name, args)

        [name, args]
      end

      # Binds the parameters of `b` to `args` in `env`.
      #: (Block b, Array[String] args, Hash[String, String] env) -> void
      def bind(b, args, env)
        b.params.each_with_index { |(v, _), n| env[v] = env.fetch(args[n], args[n]) }
      end

      # The edge after `b`, if `b` only jumps or only branches on a compare
      # that `env` and the constants decide.
      #: (Block b, Hash[String, String] env) -> [String, Array[String]]?
      def decide(b, env)
        insts = b.insts
        if insts.size == 1 && insts[0].op == :jump
          name, args = insts[0].targets[0]
          return [name, args.map { |a| env.fetch(a, a) }]
        end
        return unless insts.size == 2 && insts[1].op == :brif

        cmp, br = insts #: [Inst, Inst]
        return unless cmp.op == :icmp && br.args[0] == cmp.results[0]

        held = compare(cmp, env)
        return if held.nil?

        name, args = br.targets[held ? 0 : 1]
        [name, args.map { |a| env.fetch(a, a) }]
      end

      # A skipped run must decide on a constant somewhere: a run of jumps
      # alone is the `Blocks` pass's work.
      #: (Array[Block] skipped) -> bool
      def constant_edge?(skipped) = skipped.any? { |b| b.insts.size == 2 }

      # The result of the compare `cmp`, when both operands are constants.
      #: (Inst cmp, Hash[String, String] env) -> bool?
      def compare(cmp, env)
        a, type = @const[env.fetch(cmp.args[0], cmp.args[0])]
        b, = @const[env.fetch(cmp.args[1], cmp.args[1])]
        return if a.nil? || b.nil?

        bits = type == "i64" ? 64 : 32
        a, b = signed(a, bits), signed(b, bits) if SIGNED.include?(cmp.cond)
        case cmp.cond
        when "eq" then a == b
        when "ne" then a != b
        when "slt", "ult" then a < b
        when "sle", "ule" then a <= b
        when "sgt", "ugt" then a > b
        when "sge", "uge" then a >= b
        end
      end

      #: (Integer raw, Integer bits) -> Integer
      def signed(raw, bits)
        top = 1 << (bits - 1)
        raw >= top ? raw - (top << 1) : raw
      end

      # Whether the edge can go to `name` with `args`: no argument is made
      # in a skipped block, and for each skipped block, no block that reads
      # a value made there is reachable from `name` other than through it.
      #: (Array[Block] skipped, String name, Array[String] args) -> bool
      def safe?(skipped, name, args)
        made = skipped.to_h { |b| [b, b.params.map(&:first) + b.insts.flat_map(&:results)] }
        return false if args.any? { |a| made.each_value.any? { |vs| vs.include?(a) } }

        skipped.all? do |b|
          readers = made[b].each_with_object(Set.new) { |v, set| set.merge(@read_in[v]) }
          readers.delete(b.name)
          readers.empty? || !reaches?(name, b.name, readers)
        end
      end

      # Whether `from` reaches a block in `targets` without passing `stop`.
      #: (String from, String stop, Set[String] targets) -> bool
      def reaches?(from, stop, targets)
        seen = Set[stop]
        work = [from]
        until work.empty?
          name = work.pop #: String
          next unless seen.add?(name)
          return true if targets.include?(name)

          @named.fetch(name).insts.last&.targets&.each { |(t, _)| work << t }
        end
        false
      end
    end
  end
end
