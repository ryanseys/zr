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
      # @rbs @slot_of: Hash[String, Integer]

      private

      # `address value => load type` of each slot that qualifies. A slot that
      # no load reads has type nil: its stores are dead.
      #: () -> Hash[String, String?]
      def candidates
        @slot_of = {}
        @f.blocks.each do |b|
          b.insts.each do |i|
            next unless i.op == :stack_addr

            slot = i.args[0].delete_prefix("ss").to_i
            @slot_of[i.results[0]] = slot if @f.slots[slot].bytes == 8
          end
        end
        return {} if @slot_of.empty?

        type = @slot_of.transform_values { nil } #: Hash[String, String?]
        # Untyped: `type.except(*refused)` splats a Set, and Steep types a
        # splat only of an Array.
        refused = Set.new #: untyped
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
              escapes(i.args, type, refused)
            end
            i.targets&.each { |_, args| escapes(args, type, refused) }
          end
        end
        type.except(*refused)
      end

      # If the address of a slot is in `args`, the slot does not qualify.
      #: (Array[untyped] args, Hash[String, String?] type, Set[String] refused) -> void
      def escapes(args, type, refused)
        args.each { |a| refused << a if type.key?(a) }
      end

      # A store is a write. A load gets the value of the last store in the
      # block, or the value at block entry.
      #: (Block b, Hash[String, String?] slots, Hash[String, String] last, Array[[String, Block, String]] reads) -> void
      def walk(b, slots, last, reads)
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

      # A read of a slot that no load reads cannot happen, so `type` is a
      # String here.
      #: (String _addr, String type) -> String
      def initial(_addr, type) = @f.iconst(type, 0)

      #: (Hash[String, String?] slots) -> void
      def rewrite(slots)
        @f.blocks.each do |b|
          b.insts.reject! do |i|
            case i.op
            when :stack_addr then slots.key?(i.results[0])
            when :load then slots.key?(i.args[0])
            when :store then slots.key?(i.args[1])
            end
          end
        end
        slots.each_key { |addr| @f.slots[@slot_of.fetch(addr)].bytes = 0 }
      end
    end
  end
end
