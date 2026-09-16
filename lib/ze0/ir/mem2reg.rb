# frozen_string_literal: true

module Ze0
  module IR
    # Stack slots to SSA values, over a finished function.
    #
    # The kernel dialect gives every local a slot, and a slot costs a
    # store at every assignment and a load at every read: most of what a
    # kernel function did was move words between registers and its frame,
    # and the register allocator, which sees only values, could do
    # nothing about it. A slot the function only ever loads and stores
    # whole, through its address, is a variable no one else can see. Each
    # load is then the value the last store on the way there put, and a
    # block that different stores reach takes that value as a parameter.
    #
    # Which slots: eight bytes, and an address used for nothing but a load
    # or a store through it at offset 0. An address passed to a call, added
    # to, carried to a block or stored somewhere keeps its slot. That is
    # also why no root is lost: the collector reads the kernel's root
    # frames and the task's frame records, and it reaches both through an
    # address that was stored or passed, which keeps them in memory.
    #
    # The construction is Braun et al.'s, over a CFG that is already
    # complete, so every block is sealed from the start: a read with no
    # store ahead of it in its block asks its predecessors, a block with
    # several makes a parameter first, and a parameter every edge gives the
    # same value is that value. A path with no store at all reads zero.
    #
    # A `brif` carries no arguments, so every edge one enters a join by
    # is split first: a block of its own that jumps on, laid out before
    # the join so it falls into it. One that ends up carrying nothing
    # `IR::Passes::Blocks` jumps past again: this runs in the kernel
    # lowering, before `IR::Passes`.
    class Mem2Reg
      def self.run(f) = new(f).run

      def initialize(f)
        @f = f
      end

      def run
        slots = candidates
        return @f if slots.empty?

        @preds = predecessors
        return @f if @preds[@f.entry_block.name]&.any?

        split_edges
        plan(slots)
        apply(slots)
        @f
      end

      private

      # `address value => load type` of every slot that qualifies. A slot
      # no load reads has type nil: its stores are dead.
      def candidates
        @slot_of = {}
        @f.blocks.each do |b|
          b.insts.each { |i| @slot_of[i.results[0]] = i.args[0].delete_prefix("ss").to_i if i.op == :stack_addr && @f.slots[i.args[0].delete_prefix("ss").to_i].bytes == 8 }
        end
        return {} if @slot_of.empty?

        type = @slot_of.transform_values { nil }
        refused = Set.new
        @f.blocks.each do |b|
          b.insts.each do |i|
            case i.op
            when :load
              addr = i.args[0]
              next unless type.key?(addr)

              refused << addr if i.offset != 0 || (type[addr] && type[addr] != i.type)
              type[addr] = i.type
            when :store
              value, addr = i.args
              refused << value if type.key?(value)
              refused << addr if type.key?(addr) && i.offset != 0
            else
              i.args.each { |a| refused << a if type.key?(a) }
            end
            i.targets&.each { |(_, args)| args.each { |a| refused << a if type.key?(a) } }
          end
        end
        type.reject { |addr, _| refused.include?(addr) }
      end

      # Every block's predecessors, by the terminators that reach it: a
      # block a `brif` reaches twice lists it twice.
      def predecessors
        preds = Hash.new { |h, k| h[k] = [] }
        @f.blocks.each do |b|
          b.insts.last&.targets&.each { |(name, _)| preds[name] << b }
        end
        preds
      end

      # A block of its own on each `brif` edge into a block with more
      # than one predecessor, so that every edge into a join is a jump
      # that can carry the join's parameters.
      def split_edges
        @f.blocks.dup.each do |join|
          next if @preds[join.name].size < 2

          @preds[join.name].map! do |p|
            br = p.insts.last
            next p unless br.op == :brif

            side = @f.block_before(join)
            side.insts << IR::Inst.new(:jump, targets: [[join.name, []]])
            k = br.targets.index { |(name, _)| name == join.name }
            br.targets[k] = [side.name, []]
            @preds[side.name] = [p]
            side
          end
        end
      end

      # Every load's value, and every parameter a join needs, for the
      # slots in `slots`: `@rename` maps a load's result to what it reads.
      def plan(slots)
        @rename = {}
        @last = Hash.new { |h, k| h[k] = {} }
        @entering = Hash.new { |h, k| h[k] = {} }
        @joins = []
        @incoming = {}
        @work = []
        reads = []
        @f.blocks.each do |b|
          last = @last[b.name]
          b.insts.each do |i|
            if i.op == :store && slots.key?(i.args[1])
              last[i.args[1]] = i.args[0]
            elsif i.op == :load && slots.key?(i.args[0])
              addr = i.args[0]
              if last.key?(addr)
                @rename[i.results[0]] = last[addr]
              else
                reads << [i.results[0], b, addr]
              end
            end
          end
        end
        reads.each { |result, b, addr| @rename[result] = entering(b, addr, slots) }
        until @work.empty?
          param, b, addr = @work.pop
          @incoming[param] = @preds[b.name].map { |p| leaving(p, addr, slots) }
        end
        drop_trivial(slots)
      end

      # The value of `addr`'s variable where control enters `b`.
      def entering(b, addr, slots)
        seen = @entering[addr]
        return seen[b.name] if seen.key?(b.name)

        from = @preds[b.name]
        seen[b.name] = case from.size
                       when 0 then @f.iconst(slots.fetch(addr), 0)
                       when 1 then leaving(from[0], addr, slots)
                       else
                         param = @f.value
                         @joins << [param, b, addr]
                         @work << [param, b, addr]
                         param
                       end
      end

      def leaving(b, addr, slots)
        @last[b.name].fetch(addr) { entering(b, addr, slots) }
      end

      # A parameter every edge gives one value, or only itself, is that
      # value; taking one away can make another trivial.
      def drop_trivial(slots)
        loop do
          dropped = false
          @joins.each do |param, _, addr|
            next if @rename.key?(param)

            others = @incoming[param].map { |v| resolve(v) }.uniq
            others.delete(param)
            next if others.size > 1

            @rename[param] = others[0] || @f.iconst(slots.fetch(addr), 0)
            dropped = true
          end
          break unless dropped
        end
        @joins.reject! { |param, _, _| @rename.key?(param) }
      end

      def resolve(v)
        v = @rename[v] while @rename.key?(v)
        v
      end

      def apply(slots)
        @joins.each do |param, b, addr|
          b.params << [param, slots.fetch(addr)]
          # A new Array and not `<<`: two jumps may share one.
          @preds[b.name].zip(@incoming[param]) { |p, v| (edge = p.insts.last.targets[0])[1] = edge[1] + [v] }
        end
        @f.blocks.each do |b|
          b.insts.reject! do |i|
            case i.op
            when :stack_addr then slots.key?(i.results[0])
            when :load then slots.key?(i.args[0])
            when :store then slots.key?(i.args[1])
            end
          end
          b.insts.each do |i|
            i.args.map! { |a| resolve(a) }
            i.targets&.each { |(_, args)| args.map! { |a| resolve(a) } }
          end
        end
        slots.each_key { |addr| @f.slots[@slot_of.fetch(addr)].bytes = 0 }
      end
    end
  end
end
