# frozen_string_literal: true

require_relative "promotion"

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
    # A path with no store at all reads zero. This runs in the kernel
    # lowering, before `IR::Passes`; a split edge that ends up carrying
    # nothing `IR::Passes::Blocks` jumps past again.
    class Mem2Reg < Promotion
      private

      # `address value => load type` of every slot that qualifies. A slot
      # no load reads has type nil: its stores are dead.
      def candidates
        @slot_of = {}
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          insts = blocks[bi].insts
          n = 0
          while n < insts.size
            i = insts[n]
            n += 1
            next unless i.op == :stack_addr

            slot = i.args[0].delete_prefix("ss").to_i
            @slot_of[i.results[0]] = slot if @f.slots[slot].bytes == 8
          end
          bi += 1
        end
        return {} if @slot_of.empty?

        type = @slot_of.transform_values { nil }
        refused = Set.new
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          insts = blocks[bi].insts
          n = 0
          while n < insts.size
            i = insts[n]
            n += 1
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
              escapes(i.args, type, refused)
            end
            targets = i.targets
            next unless targets

            k = 0
            while k < targets.size
              escapes(targets[k][1], type, refused)
              k += 1
            end
          end
          bi += 1
        end
        type.reject { |addr, _| refused.include?(addr) }
      end

      # A slot whose address is among `args` is refused.
      def escapes(args, type, refused)
        k = 0
        while k < args.size
          a = args[k]
          refused << a if type.key?(a)
          k += 1
        end
      end

      # A store is the write; a load reads what the last store in the
      # block put, or asks what entered.
      def walk(b, slots, last, reads)
        insts = b.insts
        n = 0
        while n < insts.size
          i = insts[n]
          n += 1
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

      def initial(_addr, type) = @f.iconst(type, 0)

      def rewrite(slots)
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          blocks[bi].insts.reject! do |i|
            case i.op
            when :stack_addr then slots.key?(i.results[0])
            when :load then slots.key?(i.args[0])
            when :store then slots.key?(i.args[1])
            end
          end
          bi += 1
        end
        slots.each_key { |addr| @f.slots[@slot_of.fetch(addr)].bytes = 0 }
      end
    end
  end
end
