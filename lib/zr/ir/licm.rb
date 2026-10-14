# frozen_string_literal: true

require_relative "effects"
require_relative "gvn"
require_relative "regions"

module Zr
  module IR
    # Loop-invariant code motion. If an instruction computes the same
    # value in each iteration of a natural loop, the pass moves it to
    # the preheader of the loop.
    #
    # A pure, single-result instruction (`GVN::PURE`) is invariant when
    # all its operands come from outside the loop or from moved
    # instructions. Two kinds stay in the loop:
    # - An instruction with no value operands (a constant, an address),
    #   because a backend makes it where it is used.
    # - A value that only branches read, directly or through a `band` or
    #   `bor`. A backend folds the compare into the branch; a moved value
    #   would use a register for the full loop.
    #
    # A load is invariant when its address is invariant and nothing in
    # the loop can write its region (see `Regions`). A hoisted load must
    # not fault if the loop runs zero times. Thus a load moves only if
    # the address is a static, or a load or store of the same address
    # and offset dominates the header, or the block of the load
    # dominates all loop exits. A volatile load never moves. `Forward`
    # and `Mem2Reg` handle slot loads.
    #
    # The pass makes the preheader when the first instruction moves. The
    # preheader goes before the header, takes the header parameters and
    # jumps to the header. Inner loops go first, so an instruction can
    # move out of more than one loop.
    class LICM
      # @rbs @analysis: Analysis
      # @rbs @block: Hash[String, Block]
      # @rbs @header_of: Hash[String, String]
      # @rbs @moved: bool
      # @rbs @tested: Hash[String, bool]
      # @rbs @rank: Hash[String, Integer]
      # @rbs @pre_of: Hash[String, Block]
      # @rbs @body: Hash[Analysis::Loop, Hash[String, bool]]
      # @rbs @loop: Analysis::Loop
      # @rbs @in: Hash[String, bool]
      # @rbs @variant: Hash[String, bool]
      # @rbs @written: Integer
      # @rbs @exits: Array[String]
      # @rbs @read: Hash[[String, Integer], bool]

      include Regions

      #: (Function f) -> Function
      def self.run(f) = new(f).run

      #: (Function f) -> void
      def initialize(f)
        @f = f
        @analysis = f.analysis
        @effects = f.callees.to_h { |c| [c.fn, c.effects || Effects::ALL] }
        @block = f.blocks.to_h { |b| [b.name, b] }
        @header_of = {}
        @moved = false
      end

      #: () -> Function
      def run
        loops = @analysis.loops
        return @f if loops.empty?

        @placed = placements
        @tested = tested_only
        # Each block's place in reverse postorder, two apart, so that a
        # preheader takes the place just before its header.
        @rank = @analysis.rpo.each_with_index.to_h { |b, i| [b.name, 2 * i] }
        @pre_of = {}
        @body = loops.to_h { |l| [l, l.body.to_h { |b| [b, true] }] }
        entry = @f.entry_block.name
        loops.reverse_each { |l| hoist(l, loops) unless l.header == entry }
        return @f unless @moved

        @f.place_before(@pre_of.transform_values { |pre| [pre] })
        @f.changed!(:cfg)
      end

      private

      # Moves each invariant instruction of `loop` to its preheader.
      #: (Analysis::Loop loop, Array[Analysis::Loop] loops) -> void
      def hoist(loop, loops)
        @loop = loop
        @in = @body.fetch(loop)
        survey
        pre = nil #: Block?
        # The loop's own reachable blocks, in reverse postorder.
        @in.each_key.select { |name| @rank.key?(name) }.sort_by! { |name| @rank.fetch(name) }.each do |name|
          insts = @block.fetch(name).insts
          # `while`: a moved instruction leaves `insts`.
          n = 0
          while n < insts.size
            i = insts[n]
            unless invariant?(i, name)
              n += 1
              next
            end

            insts.delete_at(n)
            into = pre ||= preheader(loop, loops)
            into.insts.insert(-2, i)
            i.results.each { |v| @variant.delete(v) }
          end
        end
      end

      # Collects facts about the loop:
      # `@variant`: the values that the body defines.
      # `@written`: the regions that the loop can write.
      # `@exits`: the blocks that leave the loop (all latches if none do).
      # `@read`: each `[address, offset]` that a block which dominates
      # the header loads or stores: each block up the header's dominator
      # chain, and the preheader that this pass made for one of them.
      #: () -> void
      def survey
        @variant = {}
        @written = 0
        @exits = []
        @in.each_key do |name|
          b = @block.fetch(name)
          @written |= writes_of(b)
          b.params.each { |(v, _)| @variant[v] = true }
          b.insts.each { |i| i.results.each { |v| @variant[v] = true } }
          @exits << name if leaves?(b.insts.last.targets)
        end
        @exits = @loop.latches if @exits.empty?
        @read = {}
        idom = @analysis.idom
        name = @loop.header #: String?
        while (name = idom[name])
          reads(@block.fetch(name))
          pre = @pre_of[name]
          reads(pre) if pre
        end
      end

      # Adds each `[address, offset]` that `b` loads or stores to `@read`.
      #: (Block b) -> void
      def reads(b)
        b.insts.each do |i|
          case i.op
          when :load then @read[[i.args[0], i.offset]] = true
          when :store then @read[[i.args[1], i.offset]] = true
          end
        end
      end

      # Whether any of `targets` is outside the loop.
      #: (Array[[String, Array[String]]]? targets) -> bool
      def leaves?(targets)
        return false unless targets

        targets.any? { |name, _| !@in.key?(name) }
      end

      # Whether `i`, in the loop block `at`, gives the same value in each
      # iteration and can run before the first iteration.
      #: (Inst i, String at) -> bool
      def invariant?(i, at)
        return load_invariant?(i, at) if i.op == :load

        return false if i.results.size != 1 || !GVN::PURE.include?(i.op) || @tested.key?(i.results[0])

        values = i.args.select { |a| IR.value?(a) }
        return false if values.any? { |a| @variant.key?(a) }

        values.any?
      end

      #: (Inst i, String at) -> bool
      def load_invariant?(i, at)
        addr = i.args[0]
        return false if @variant.key?(addr)

        region = region_of(i, addr)
        return false if region == :volatile || region == :slot
        return false unless (@written & (region ? Effects.bit(region) : Effects::ALL)).zero?

        @placed.key?(addr) || @read.key?([addr, i.offset]) || dominates_exits?(at)
      end

      # Returns `{ value => true }` for each value that only branches
      # read, directly or through a `band` or `bor` that only branches
      # read. `Chains` changes such a `band` or `bor` into branches. The
      # loop repeats until nothing changes, because one pass can find
      # new values for the next.
      #: () -> Hash[String, bool]
      def tested_only
        uses = @analysis.uses
        reads = Hash.new(0) #: Hash[String, Integer]
        blocks = @f.blocks
        blocks.each do |b|
          br = b.insts.last
          reads[br.args[0]] += 1 if br.op == :brif || br.op == :switch
        end
        tested = {} #: Hash[String, bool]
        loop do
          moved = false
          blocks.each do |b|
            b.insts.each do |i|
              v = i.results[0]
              next if tested.key?(v) || reads[v].zero? || reads[v] != uses.fetch(v, 0)

              tested[v] = true
              moved = true
              next unless i.op == :band || i.op == :bor

              i.args.each { |a| reads[a] += 1 if IR.value?(a) }
            end
          end
          break unless moved
        end
        tested
      end

      #: (String at) -> bool
      def dominates_exits?(at)
        @exits.all? { |x| dominates?(at, x) }
      end

      # A preheader that this pass made dominates all that its header
      # dominates.
      #: (String a, String b) -> bool
      def dominates?(a, b)
        a == b || @analysis.dominates?(@header_of.fetch(a, a), b)
      end

      # Makes a new block for the edges into the header of `loop` from
      # outside the loop. Each such edge changes to target the new block.
      # The block takes the header parameters and jumps to the header
      # with them. Moved instructions go before the jump. The block
      # becomes part of the body of each loop that contains this loop.
      #: (Analysis::Loop loop, Array[Analysis::Loop] loops) -> Block
      def preheader(loop, loops)
        @moved = true
        header = @block.fetch(loop.header)
        # `run` places it before the header with the other preheaders.
        pre = @f.unplaced_block
        params = header.params.map { |(_, type)| [@f.value, type] } #: Array[[String, String]]
        pre.params.concat(params)
        pre.insts << Inst.new(:jump, targets: [[header.name, params.map(&:first)]])
        @analysis.preds.fetch(header.name).uniq.each do |p|
          next if @in.key?(p)

          # Make a new pair; do not change the old pair, because two
          # jumps can share it.
          @block.fetch(p).insts.last.targets.map! { |t| t[0] == header.name ? [pre.name, t[1]] : t }
        end
        @block[pre.name] = pre
        @header_of[pre.name] = header.name
        @pre_of[header.name] = pre
        @rank[pre.name] = @rank.fetch(header.name) - 1
        loops.each { |l| @body.fetch(l)[pre.name] = true if l != loop && @body.fetch(l).key?(header.name) }
        pre
      end
    end
  end
end
