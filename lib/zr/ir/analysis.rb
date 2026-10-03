# frozen_string_literal: true

require_relative "inst"

module Zr
  module IR
    # Facts about the shape of a function, calculated one time and kept:
    # the predecessors of each block, the blocks in reverse postorder, the
    # dominator tree with pre- and post-numbers (so `dominates?` is two
    # compares), the number of reads of each value, and the natural loops.
    # `Function#analysis` keeps one until a pass reports a change.
    #
    # A pass that adds, removes or retargets a block or an edge calls
    # `f.changed!(:cfg)`, and the next `analysis` is calculated again. A
    # pass that changes only instructions calls `f.changed!(:insts)`: the
    # graph facts stay and the use counts are cleared. `Verify::Strict`
    # calculates the facts again and rejects a kept analysis that is
    # different, so a missing `changed!` fails the tests.
    #
    # Each fact is calculated at its first use, so a pass that needs only
    # the predecessors does not calculate the dominators. Facts refer to
    # blocks by name, because passes use names. `rpo` contains the blocks
    # themselves, because a walk needs their instructions.
    class Analysis
      # @rbs @f: Function
      # @rbs @blocks: Hash[String, Block]
      # @rbs @preds: Hash[String, Array[String]]?
      # @rbs @rpo: Array[Block]
      # @rbs @idom: Hash[String, String?]?
      # @rbs @pre: Hash[String, Integer]
      # @rbs @post: Hash[String, Integer]
      # @rbs @uses: Hash[String, Integer]?
      # @rbs @loops: Array[Loop]
      # @rbs @depth: Hash[String, Integer]

      # A natural loop: its header, all its blocks (header first), the
      # blocks whose back edge closes it, and its depth (the number of loops
      # that contain it, itself included).
      class Loop
        attr_reader :header #: String
        attr_reader :body #: Array[String]
        attr_reader :latches #: Array[String]
        attr_accessor :depth #: Integer

        #: (String header) -> void
        def initialize(header)
          @header = header
          @body = [header]
          @latches = []
          @depth = 1
        end
      end

      # `@rpo`, `@pre`, `@post`, `@loops` and `@depth` are nil until their
      # first use sets them, so their types do not include nil.
      #: (Function f) -> void
      def initialize(f)
        @f = f
        @blocks = f.blocks.to_h { |b| [b.name, b] }
        @preds = nil
        @rpo = nil #: untyped
        @idom = nil
        @pre = nil #: untyped
        @post = nil #: untyped
        @uses = nil
        @loops = nil #: untyped
        @depth = nil #: untyped
      end

      # `{ block name => [predecessor name, ...] }`, one entry for each edge.
      # A block that a `brif` reaches on both arms lists that predecessor two
      # times. Each block has an entry; an unreachable block has an empty list.
      #: () -> Hash[String, Array[String]]
      def preds
        @preds ||= begin
          into = @f.blocks.to_h do |b|
            names = [] #: Array[String]
            [b.name, names]
          end
          @f.blocks.each { |b| b.insts.last&.targets&.each { |(name, _)| into[name] << b.name } }
          into
        end
      end

      # The blocks that the entry reaches, in reverse postorder: a block
      # comes before each block that it dominates, and a loop header comes
      # before its body. Unreachable blocks are not included.
      #: () -> Array[Block]
      def rpo
        @rpo ||= postorder.reverse
      end

      # `{ block name => immediate dominator name }` for the reachable
      # blocks; nil for the entry. This is the iterative algorithm of Cooper,
      # Harvey and Kennedy over the reverse postorder.
      #: () -> Hash[String, String?]
      def idom
        @idom ||= dominators
      end

      # Whether `a` dominates `b` (a block dominates itself): two compares of
      # the pre- and post-numbers of the dominator tree. An unreachable block
      # dominates nothing, and nothing dominates it.
      #: (String a, String b) -> bool
      def dominates?(a, b)
        number unless @pre
        pa = @pre[a]
        pb = @pre[b]
        return false unless pa && pb

        pa <= pb && @post[b] <= @post[a]
      end

      # `{ value => number of operands that read it }`, jump arguments
      # included. A value that nothing reads has no entry: use
      # `uses.fetch(v, 0)`.
      #: () -> Hash[String, Integer]
      def uses
        @uses ||= begin
          # The values are untyped only so that `default = nil` checks.
          counts = Hash.new(0) #: Hash[String, untyped]
          @f.blocks.each do |b|
            b.insts.each do |i|
              i.args.each { |a| counts[a] += 1 if IR.value?(a) }
              i.targets&.each { |(_, args)| args.each { |a| counts[a] += 1 if IR.value?(a) } }
            end
          end
          counts.default = nil
          counts
        end
      end

      # The natural loops, outermost first, one for each header. Each back
      # edge (an edge to a block that dominates its source) adds to a loop.
      # The body is each block that reaches a latch without the header. Two
      # back edges to one header make one loop.
      #: () -> Array[Loop]
      def loops
        @loops ||= natural_loops
      end

      # The number of loops that contain `block`: 0 when outside all loops.
      # Only the tests use it (test/unit/analysis_test.rb).
      #: (String block) -> Integer
      def depth_of(block)
        loops unless @depth
        @depth.fetch(block, 0)
      end

      # What `changed!(:insts)` keeps: the graph facts stay, and the use
      # counts are cleared.
      #: () -> self
      def insts_changed!
        @uses = nil
        self
      end

      # Whether `other`, calculated again from the function, gives the same
      # values for the facts that this one calculated. The strict check uses
      # this on a kept analysis.
      #: (Analysis other) -> bool
      def same_as?(other)
        (@preds.nil? || @preds == other.preds) &&
          (@rpo.nil? || @rpo.map(&:name) == other.rpo.map(&:name)) &&
          (@idom.nil? || @idom == other.idom) &&
          (@uses.nil? || @uses == other.uses) &&
          (@loops.nil? || @loops.map { |l| [l.header, l.body, l.latches] } == other.loops.map { |l| [l.header, l.body, l.latches] })
      end

      private

      #: (Block b) -> Array[String]
      def successors(b) = (b.insts.last&.targets || []).map(&:first)

      #: () -> Array[Block]
      def postorder
        entry = @f.entry_block
        seen = { entry.name => true }
        out = [] #: Array[Block]
        stack = [[entry, 0]] #: Array[[Block, Integer]]
        until stack.empty?
          frame = stack.last #: [Block, Integer]
          b, k = frame
          names = successors(b)
          if k < names.size
            frame[1] += 1
            s = @blocks.fetch(names[k])
            next if seen[s.name]

            seen[s.name] = true
            stack << [s, 0]
          else
            stack.pop
            out << b
          end
        end
        out
      end

      # On the positions in the reverse postorder, not the names: a step of
      # `intersect` is then two array reads (0.17 s to 0.05 s for a function
      # of 23,000 blocks). A predecessor that the entry does not reach has
      # no position. The first round sets each block, in the reverse
      # postorder, and the table keeps that order.
      #: () -> Hash[String, String?]
      def dominators
        order = rpo
        at = order.each_with_index.to_h { |b, n| [b.name, n] }
        from = order.map { |b| preds.fetch(b.name).filter_map { |p| at[p] } }
        doms = Array.new(order.size) #: Array[Integer]
        doms[0] = 0
        loop do
          changed = false
          (1...order.size).each do |n|
            new = nil #: Integer?
            from[n].each do |p|
              next unless doms[p]

              new = new ? intersect(new, p, doms) : p
            end
            if new && doms[n] != new
              doms[n] = new
              changed = true
            end
          end
          break unless changed
        end
        idom = { order[0].name => nil } #: Hash[String, String?]
        (1...order.size).each { |n| idom[order[n].name] = order[doms[n]].name if doms[n] }
        idom
      end

      #: (Integer a, Integer b, Array[Integer] doms) -> Integer
      def intersect(a, b, doms)
        until a == b
          a = doms[a] while a > b
          b = doms[b] while b > a
        end
        a
      end

      # The pre- and post-numbers of the dominator tree, from one walk. A
      # child of a block is a block whose immediate dominator is that block.
      #: () -> void
      def number
        children = Hash.new { |h, k| h[k] = [] } #: Hash[String, Array[String]]
        idom.each { |b, d| children[d] << b if d }
        @pre = {}
        @post = {}
        n = 0
        stack = [[@f.entry_block.name, 0]] #: Array[[String, Integer]]
        @pre[@f.entry_block.name] = n
        until stack.empty?
          frame = stack.last #: [String, Integer]
          b, k = frame
          kids = children[b]
          if k < kids.size
            frame[1] += 1
            @pre[kids[k]] = (n += 1)
            stack << [kids[k], 0]
          else
            @post[b] = (n += 1)
            stack.pop
          end
        end
      end

      #: () -> Array[Loop]
      def natural_loops
        by_header = {} #: Hash[String, Loop]
        rpo.each do |b|
          successors(b).each do |h|
            next unless dominates?(h, b.name)

            loop = by_header[h] ||= Loop.new(h)
            loop.latches << b.name
            collect(loop, b.name)
          end
        end
        loops = by_header.values
        # The depth of a loop is the number of loops that contain its header.
        # The depth of a block is the depth of its innermost loop.
        @depth = {}
        loops.each { |l| l.depth = loops.count { |o| o.body.include?(l.header) } }
        loops.sort_by!(&:depth)
        loops.each { |l| l.body.each { |b| @depth[b] = l.depth } }
        loops
      end

      # Adds to the body each block that reaches `from` backwards without the
      # loop header.
      #: (Loop loop, String from) -> void
      def collect(loop, from)
        seen = loop.body.to_h { |b| [b, true] }
        work = [from]
        until work.empty?
          b = work.pop #: String
          next if seen[b]

          seen[b] = true
          loop.body << b
          preds.fetch(b).each { |p| work << p unless seen[p] }
        end
      end
    end
  end
end
