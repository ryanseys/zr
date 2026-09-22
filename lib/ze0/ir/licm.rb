# frozen_string_literal: true

require_relative "effects"
require_relative "gvn"
require_relative "regions"

module Ze0
  module IR
    # Loop-invariant code motion: an instruction a loop computes the
    # same at every turn is computed once, before the loop.
    #
    # The loops are the analysis's natural loops. An instruction with
    # no effect and one result (`GVN::PURE`) whose operands are all
    # defined outside the loop, or by an instruction already moved, is
    # invariant; one that reads no value (a constant, an address)
    # stays, since a backend makes those where they are used, and so
    # does one that only a branch reads, itself or through a `band` or
    # `bor` that only a branch reads: a backend folds a compare or a
    # bit test into its branch, and moved out it would hold a register
    # through every turn for what one instruction answers.
    #
    # A load is invariant when its address is and nothing in the loop
    # can write its region (`Regions`: a store to it, a store placed
    # nowhere, a call whose effects include it, a call through a
    # pointer). It moves only where the word is known to be there
    # before the loop, since a loop that turns no times reads nothing,
    # and a hoisted load of a null pointer is a fault the program never
    # had: the address is a static's, or a load or a store of the same
    # address and offset dominates the header, or the load's own block
    # dominates every block the loop leaves from, so any turn that ends
    # reads it. A load of the volatile region is never invariant, and a
    # slot's is `Forward`'s and `Mem2Reg`'s.
    #
    # What moves goes to the loop's preheader: a block of its own on
    # the edges into the header, made when the first instruction moves,
    # laid out before the header so it falls into it. The header's
    # parameters, if it has any, the preheader takes and passes on.
    #
    # The inner loops go first, so what leaves one lands in its
    # preheader, inside the loop around it, and may leave that too. A
    # preheader dominates what its header dominates.
    class LICM
      include Regions

      def self.run(f) = new(f).run

      def initialize(f)
        @f = f
        @analysis = f.analysis
        @effects = f.callees.to_h { |c| [c.fn, c.effects || Effects::ALL] }
        @block = f.blocks.to_h { |b| [b.name, b] }
        @header_of = {}
        @moved = false
      end

      def run
        loops = @analysis.loops
        return @f if loops.empty?

        @placed = placements
        @tested = tested_only
        @order = @analysis.rpo.map(&:name)
        @body = loops.to_h { |l| [l, l.body.to_h { |b| [b, true] }] }
        entry = @f.entry_block.name
        k = loops.size
        while k.positive?
          k -= 1
          hoist(loops[k], loops) unless loops[k].header == entry
        end
        @moved ? @f.changed!(:cfg) : @f
      end

      private

      # Every invariant instruction of `loop` moves to its preheader.
      def hoist(loop, loops)
        @loop = loop
        @in = @body.fetch(loop)
        survey
        pre = nil
        order = @order
        k = 0
        while k < order.size
          name = order[k]
          k += 1
          next unless @in.key?(name)

          insts = @block.fetch(name).insts
          n = 0
          while n < insts.size
            i = insts[n]
            unless invariant?(i, name)
              n += 1
              next
            end

            insts.delete_at(n)
            pre ||= preheader(loop, loops)
            pre.insts.insert(-2, i)
            i.results.each { |v| @variant.delete(v) }
          end
        end
      end

      # What the loop says of itself: `@variant`, the values its body
      # defines; `@written`, the regions it may write; `@exits`, the
      # blocks it leaves from, or every latch when it leaves from none;
      # `@read`, each `[address, offset]` a block that dominates the
      # header loads or stores.
      def survey
        @variant = {}
        @written = 0
        @exits = []
        @in.each_key do |name|
          b = @block.fetch(name)
          @written |= writes_of(b)
          b.params.each { |(v, _)| @variant[v] = true }
          insts = b.insts
          n = 0
          while n < insts.size
            insts[n].results.each { |v| @variant[v] = true }
            n += 1
          end
          @exits << name if leaves?(insts.last.targets)
        end
        @exits = @loop.latches if @exits.empty?
        @read = {}
        header = @loop.header
        order = @order
        k = 0
        while k < order.size
          name = order[k]
          k += 1
          next if @in.key?(name) || !dominates?(name, header)

          insts = @block.fetch(name).insts
          n = 0
          while n < insts.size
            i = insts[n]
            n += 1
            case i.op
            when :load then @read[[i.args[0], i.offset]] = true
            when :store then @read[[i.args[1], i.offset]] = true
            end
          end
        end
      end

      # Whether any of `targets` is outside the loop.
      def leaves?(targets)
        return false unless targets

        k = 0
        while k < targets.size
          return true unless @in.key?(targets[k][0])

          k += 1
        end
        false
      end

      # Whether `i`, in the loop's block `at`, answers the same at every
      # turn and may be computed before the first.
      def invariant?(i, at)
        return load_invariant?(i, at) if i.op == :load

        return false if i.results.size != 1 || !GVN::PURE.include?(i.op) || @tested.key?(i.results[0])

        args = i.args
        reads = false
        k = 0
        while k < args.size
          a = args[k]
          k += 1
          next unless IR.value?(a)
          return false if @variant.key?(a)

          reads = true
        end
        reads
      end

      def load_invariant?(i, at)
        addr = i.args[0]
        return false if @variant.key?(addr)

        region = region_of(i, addr)
        return false if region == :volatile || region == :slot
        return false unless (@written & (region ? Effects.bit(region) : Effects::ALL)).zero?

        @placed.key?(addr) || @read.key?([addr, i.offset]) || dominates_exits?(at)
      end

      # `{ value => true }` for every value that only branches read,
      # itself or through the `band`s and `bor`s that only branches
      # read, which `Chains` turns into branches of their own. A round
      # over those can make the next one's answers.
      def tested_only
        uses = @analysis.uses
        reads = Hash.new(0)
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          br = blocks[bi].insts.last
          reads[br.args[0]] += 1 if br.op == :brif
          bi += 1
        end
        tested = {}
        loop do
          moved = false
          bi = 0
          while bi < blocks.size
            insts = blocks[bi].insts
            n = 0
            while n < insts.size
              i = insts[n]
              n += 1
              v = i.results[0]
              next if tested.key?(v) || reads[v].zero? || reads[v] != uses.fetch(v, 0)

              tested[v] = true
              moved = true
              next unless i.op == :band || i.op == :bor

              args = i.args
              k = 0
              while k < args.size
                reads[args[k]] += 1 if IR.value?(args[k])
                k += 1
              end
            end
            bi += 1
          end
          break unless moved
        end
        tested
      end

      def dominates_exits?(at)
        exits = @exits
        k = 0
        while k < exits.size
          return false unless dominates?(at, exits[k])

          k += 1
        end
        true
      end

      # A preheader this pass made dominates what its header does.
      def dominates?(a, b)
        a == b || @analysis.dominates?(@header_of.fetch(a, a), b)
      end

      # A block of its own on the edges into `loop`'s header from
      # outside it: every such edge is retargeted to it, and it jumps
      # on with the header's parameters, which it takes as its own; what
      # moves goes in ahead of the jump. It joins the body of every loop
      # around this one.
      def preheader(loop, loops)
        @moved = true
        header = @block.fetch(loop.header)
        pre = @f.block_before(header)
        params = header.params.map { |(_, type)| [@f.value, type] }
        pre.params.concat(params)
        pre.insts << Inst.new(:jump, targets: [[header.name, params.map(&:first)]])
        @analysis.preds.fetch(header.name).uniq.each do |p|
          next if @in.key?(p)

          # A new pair and not a write into one: two jumps may share one.
          targets = @block.fetch(p).insts.last.targets
          k = 0
          while k < targets.size
            targets[k] = [pre.name, targets[k][1]] if targets[k][0] == header.name
            k += 1
          end
        end
        @block[pre.name] = pre
        @header_of[pre.name] = header.name
        @order.insert(@order.index(header.name), pre.name)
        loops.each { |l| @body.fetch(l)[pre.name] = true if l != loop && @body.fetch(l).key?(header.name) }
        pre
      end
    end
  end
end
