# frozen_string_literal: true

module Zr
  module IR
    module Passes
      # Simplifies the blocks. The pass removes a block that the entry does
      # not reach. It skips a block that only jumps and has no parameters. It
      # joins a block to its single predecessor when the block is the only
      # successor of that predecessor; the block parameters become the jump
      # arguments. One round can make work for the next, so rounds continue
      # until nothing changes. The entry block stays first and is never joined.
      class Blocks
        include Renaming

        #: (Function f) -> Function
        def self.run(f) = new(f).run

        #: (Function f) -> void
        def initialize(f)
          @f = f
          @rename = {}
        end

        #: () -> Function
        def run
          loop { break unless pruned? | bypassed? | merged? }
          rename_uses unless @rename.empty?
          @f.changed!(:cfg)
          dominance_order unless defined_first?
          @f
        end

        private

        # `{ name => [[block, k], ...] }`: each edge into a block, as the
        # predecessor and the index of the target.
        #: () -> Hash[String, Array[[Block, Integer]]]
        def edges
          into = Hash.new { |h, k| h[k] = [] } #: Hash[String, Array[[Block, Integer]]]
          @f.blocks.each do |b|
            b.insts.last&.targets&.each_with_index { |(name, _), k| into[name] << [b, k] }
          end
          into
        end

        # Each step below changes the function and answers whether it did.

        # Drops the unreachable blocks. The blocks in reverse postorder are
        # the reachable blocks.
        #: () -> bool
        def pruned?
          reached = @f.analysis.rpo
          return false if reached.size == @f.blocks.size

          @f.blocks.replace(@f.blocks & reached)
          @f.changed!(:cfg)
          true
        end

        #: () -> bool
        def bypassed?
          changed = false
          into = edges
          @f.blocks.each do |b|
            next if b.equal?(@f.entry_block) || !b.params.empty? || b.insts.size != 1 || b.insts[0].op != :jump

            name, args = b.insts[0].targets[0]
            next if name == b.name

            into[b.name].each do |p, k|
              t = p.insts.last
              next unless t.op == :jump || args.empty?

              t.targets[k] = [name, args.dup]
              changed = true
            end
          end
          @f.changed!(:cfg) if changed
          changed
        end

        # Joins all such blocks in one round, in layout order. A block that
        # takes the instructions of another block also takes its outgoing
        # edges. So a later block whose predecessor was joined joins the block
        # that took it. A predecessor after its successor in the layout moves up
        # to the successor's position. Thus each definition stays before the
        # blocks that it dominates, which `Types` needs.
        #: () -> bool
        def merged?
          into = edges
          joined = {} #: Hash[Block, bool]
                   .compare_by_identity
          laid = {} #: Hash[String, Integer]
          @f.blocks.each_with_index { |b, at| laid[b.name] = at }
          @f.blocks.each do |b|
            next if b.nil? || b.equal?(@f.entry_block) || into[b.name].size != 1

            p, = into[b.name][0]
            t = p.insts.last
            next if t.op != :jump || p.equal?(b)

            b.params.zip(t.targets[0][1]) { |(v, _), a| @rename[v] = a }
            p.insts.pop
            p.insts.concat(b.insts)
            b.insts.last&.targets&.each_with_index do |(name, _), k|
              into[name].map! { |from, at| from.equal?(b) && at == k ? [p, k] : [from, at] }
            end
            joined[b] = true
            at = laid.fetch(b.name)
            from = laid.fetch(p.name)
            next if from < at

            # The hole stays until the `reject!` below.
            holes = @f.blocks #: Array[Block?]
            holes[at] = p
            holes[from] = nil
            laid[p.name] = at
          end
          return false if joined.empty?

          @f.blocks.reject! { |b| b.nil? || joined.key?(b) }
          @f.changed!(:cfg)
          true
        end

        # Whether each value comes before its readers in the layout, as
        # `Types` needs. A join can break this: a predecessor that moves up
        # to its successor's position can move above a block that dominates
        # it, when the lowering laid the successor out before that block
        # (the exit of a `begin ... end while` loop).
        #: () -> bool
        def defined_first?
          seen = {} #: Hash[String, bool]
          @f.blocks.each { |b| b.params.each { |v, _| seen[v] = true } }
          @f.blocks.all? do |b|
            b.insts.all? do |i|
              ok = i.args.all? { |a| !IR.value?(a) || seen.key?(a) }
              i.results.each { |v| seen[v] = true }
              ok
            end
          end
        end

        # Puts each block after its immediate dominator, and keeps the order
        # of the others. A definition dominates its readers, so it then comes
        # before them. A block whose dominator comes later waits, and goes
        # just after it.
        #: () -> void
        def dominance_order
          idom = @f.analysis.idom
          waiting = Hash.new { |h, k| h[k] = [] } #: Hash[String, Array[Block]]
          placed = {} #: Hash[String, bool]
          out = [] #: Array[Block]
          @f.blocks.each do |b|
            dom = idom[b.name]
            next waiting[dom] << b if dom && !placed.key?(dom)

            ready = [b]
            while (r = ready.shift)
              out << r
              placed[r.name] = true
              children = waiting.delete(r.name)
              ready.unshift(*children) if children
            end
          end
          @f.blocks.replace(out)
          @f.changed!(:cfg)
        end
      end
    end
  end
end
