# frozen_string_literal: true

require_relative "promotion"

module Zr
  module IR
    # Promotes stack slots to SSA values in a finished function.
    #
    # The machine dialect gives each local a slot. A slot costs a store at
    # each assignment and a load at each read, and the register allocator
    # sees only values, so it cannot remove them. A slot that the function
    # only loads and stores whole, through its address, is a private
    # variable. Each load gets the value of the last store before it, and a
    # block that different stores reach takes the value as a parameter.
    #
    # A slot qualifies when it is eight bytes and its address is used only
    # for a load or a store at offset 0. An address that is passed to a
    # call, added to, passed to a block or stored keeps its slot. Thus no
    # root is lost: the collector reads the kernel root frames and the task
    # frame records through an address that was stored or passed, and such
    # a slot stays in memory.
    #
    # A path with no store reads zero. This runs in the kernel lowering,
    # before `IR::Passes`. `IR::Passes::Blocks` removes a split edge that
    # passes no values.
    class Mem2Reg < Promotion
      private

      # `address value => load type` of each slot that qualifies. A slot that
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
        type.except(*refused)
      end

      # If the address of a slot is in `args`, the slot does not qualify.
      def escapes(args, type, refused)
        k = 0
        while k < args.size
          a = args[k]
          refused << a if type.key?(a)
          k += 1
        end
      end

      # A store is a write. A load gets the value of the last store in the
      # block, or the value at block entry.
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
