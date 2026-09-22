# frozen_string_literal: true

require_relative "inst"

module Ze0
  module IR
    # What the passes ask about a function's shape, answered once and
    # kept: each block's predecessors, the blocks in reverse postorder,
    # the dominator tree with its pre- and post-numbers (so `dominates?`
    # is two compares), how many times each value is read, and the
    # natural loops. `Function#analysis` keeps one until a pass says the
    # function changed.
    #
    # The protocol is explicit. A pass that edits the graph -- adds,
    # removes or re-targets a block or an edge -- calls
    # `f.changed!(:cfg)`, and the next `analysis` is built again. One
    # that edits instructions alone calls `f.changed!(:insts)`: the
    # graph's answers stay and the use counts go. A pass that edits and
    # says nothing is caught by `Verify::Strict`, which builds the
    # answers again and refuses a kept one that differs, so a missed
    # `changed!` cannot pass the checks.
    #
    # Each answer is made when first asked, so a pass that wants the
    # predecessors alone never pays for the dominators. Every answer
    # names blocks by name, since a pass holds names; `rpo` holds the
    # blocks themselves, since a walk wants their instructions.
    class Analysis
      # A natural loop: its header, every block in it (the header
      # first), the blocks whose back edge closes it, and how many loops
      # hold it, itself counted.
      class Loop
        attr_reader :header, :body, :latches
        attr_accessor :depth

        def initialize(header)
          @header = header
          @body = [header]
          @latches = []
          @depth = 1
        end
      end

      def initialize(f)
        @f = f
        @blocks = f.blocks.to_h { |b| [b.name, b] }
        @preds = nil
        @rpo = nil
        @idom = nil
        @pre = nil
        @post = nil
        @uses = nil
        @loops = nil
        @depth = nil
      end

      # `{ block name => [predecessor name, ...] }`, an edge an entry: a
      # block a `brif` reaches on both arms lists that predecessor
      # twice. Every block has an entry, the unreached with none.
      def preds
        @preds ||= begin
          into = @f.blocks.to_h { |b| [b.name, []] }
          @f.blocks.each { |b| b.insts.last&.targets&.each { |(name, _)| into[name] << b.name } }
          into
        end
      end

      # The blocks the entry reaches, in reverse postorder: a block
      # before every block it dominates, a loop's header before its
      # body. A block nothing reaches is not here.
      def rpo
        @rpo ||= postorder.reverse
      end

      # `{ block name => immediate dominator's name }` over the reached
      # blocks, the entry's nil: Cooper, Harvey and Kennedy's iterative
      # walk over the reverse postorder.
      def idom
        @idom ||= dominators
      end

      # Whether `a` dominates `b` (a block dominates itself): two
      # compares of the dominator tree's pre- and post-numbers. A block
      # the entry does not reach dominates nothing and is dominated by
      # nothing.
      def dominates?(a, b)
        number unless @pre
        pa = @pre[a]
        pb = @pre[b]
        return false unless pa && pb

        pa <= pb && @post[b] <= @post[a]
      end

      # `{ value => how many operands read it }`, a jump's arguments
      # counted with the instructions'. A value nothing reads has no
      # entry: `uses.fetch(v, 0)`.
      def uses
        @uses ||= begin
          counts = Hash.new(0)
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

      # The natural loops, outermost first: one a header, from every
      # back edge (an edge to a block that dominates its source), the
      # body being every block that reaches a latch without passing the
      # header. Two back edges to one header make one loop.
      def loops
        @loops ||= natural_loops
      end

      # How many loops hold `block`: 0 outside every loop.
      def depth_of(block)
        loops unless @depth
        @depth.fetch(block, 0)
      end

      # What `changed!(:insts)` keeps: the graph's answers stay, the
      # use counts go.
      def insts_changed!
        @uses = nil
        self
      end

      # Whether `other`, built again from the function, answers as this
      # one does for what this one was asked: the strict check's
      # question of a kept analysis.
      def same_as?(other)
        (@preds.nil? || @preds == other.preds) &&
          (@rpo.nil? || @rpo.map(&:name) == other.rpo.map(&:name)) &&
          (@idom.nil? || @idom == other.idom) &&
          (@uses.nil? || @uses == other.uses) &&
          (@loops.nil? || @loops.map { |l| [l.header, l.body, l.latches] } == other.loops.map { |l| [l.header, l.body, l.latches] })
      end

      private

      def successors(b) = (b.insts.last&.targets || []).map(&:first)

      def postorder
        entry = @f.entry_block
        seen = { entry.name => true }
        out = []
        stack = [[entry, 0]]
        until stack.empty?
          frame = stack.last
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

      def dominators
        order = rpo
        at = order.each_with_index.to_h { |b, n| [b.name, n] }
        entry = @f.entry_block.name
        idom = { entry => entry }
        changed = true
        while changed
          changed = false
          order.drop(1).each do |b|
            new = nil
            preds.fetch(b.name).each do |p|
              next unless idom.key?(p)

              new = new ? intersect(new, p, idom, at) : p
            end
            next if new.nil? || idom[b.name] == new

            idom[b.name] = new
            changed = true
          end
        end
        idom[entry] = nil
        idom
      end

      def intersect(a, b, idom, at)
        until a == b
          a = idom[a] while at.fetch(a) > at.fetch(b)
          b = idom[b] while at.fetch(b) > at.fetch(a)
        end
        a
      end

      # The dominator tree's pre- and post-numbers, from one walk of
      # it. A child is a block whose immediate dominator this is.
      def number
        children = Hash.new { |h, k| h[k] = [] }
        idom.each { |b, d| children[d] << b if d }
        @pre = {}
        @post = {}
        n = 0
        stack = [[@f.entry_block.name, 0]]
        @pre[@f.entry_block.name] = n
        until stack.empty?
          frame = stack.last
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

      def natural_loops
        by_header = {}
        rpo.each do |b|
          successors(b).each do |h|
            next unless dominates?(h, b.name)

            loop = by_header[h] ||= Loop.new(h)
            loop.latches << b.name
            collect(loop, b.name)
          end
        end
        loops = by_header.values
        # A loop's depth is how many loops hold its header; a block's
        # is its innermost loop's.
        @depth = {}
        loops.each { |l| l.depth = loops.count { |o| o.body.include?(l.header) } }
        loops.sort_by!(&:depth)
        loops.each { |l| l.body.each { |b| @depth[b] = l.depth } }
        loops
      end

      # Every block that reaches `from` backwards without passing the
      # loop's header joins the body.
      def collect(loop, from)
        seen = loop.body.to_h { |b| [b, true] }
        work = [from]
        until work.empty?
          b = work.pop
          next if seen[b]

          seen[b] = true
          loop.body << b
          preds.fetch(b).each { |p| work << p unless seen[p] }
        end
      end
    end
  end
end
