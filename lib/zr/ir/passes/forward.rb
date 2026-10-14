# frozen_string_literal: true

module Zr
  module IR
    module Passes
      # Store-to-load forwarding for stack slots. A load from a slot at a
      # constant offset gets the value of the last store to that slot in the
      # block, if nothing between them can write the slot. The pass deletes
      # the load; the store stays as a root for the collector.
      # `Zr::Lower::Function` stores the receiver and arguments of each send
      # in record slots and loads them back at once, so this occurs at each
      # send. A call (which can get a frame address that the function passed
      # out) or a store through a non-slot address clears all known stores.
      # A store to a slot clears the stores that it overlaps.
      class Forward
        # A slot place is `[root address, offset]`. `known` maps a place to
        # `[value, width]`.
        # @rbs @types: Hash[String, String?]
        # @rbs @const: Hash[String, Integer]
        # @rbs @roots: Hash[String, [String, Integer]]

        include Renaming

        #: (Function f) -> Function
        def self.run(f) = new(f).run

        #: (Function f) -> void
        def initialize(f)
          @f = f
          @types = Types.new(f).all
          @const = {}
          @roots = {}
          @rename = {}
        end

        #: () -> Function
        def run
          @f.blocks.each { |b| forward(b) }
          rename_uses unless @rename.empty?
          @f.changed!(:insts)
        end

        private

        #: (Block b) -> void
        def forward(b)
          known = {} #: Hash[[String, Integer], [String, Integer]]
          b.insts.reject! do |i|
            rename(i)
            case i.op
            when :iconst then @const[i.results[0]] = i.args[0]
            when :stack_addr then @roots[i.results[0]] = [i.results[0], 0]
            when :iadd then note_sum(i)
            when :store then remember(known, i)
            when :load then next true if forwarded?(known, i)
            when :call, :call_indirect then known.clear
            end
            false
          end
        end

        # `v = base + k`, where `base` is a slot address, is that slot address
        # plus a constant.
        #: (Inst i) -> void
        def note_sum(i)
          a, b = i.args
          a, b = b, a if @const.key?(a)
          root, k = @roots[a]
          return unless root && @const.key?(b)

          @roots[i.results[0]] = [root, k + @const.fetch(b)]
        end

        # `[root, offset]` of the slot byte at `addr` plus `off`, or nil.
        #: (untyped addr, Integer off) -> [String, Integer]?
        def slot(addr, off)
          root, k = @roots[addr]
          root && [root, k + off]
        end

        # A store clears the known stores that it overlaps. A known store is at
        # most 8 bytes wide, so an overlapping store starts at most 7 bytes
        # below this one, or inside it. The pass checks only those keys. A scan
        # of the full table at each store is slow in a block with many stores.
        #: (Hash[[String, Integer], [String, Integer]] known, Inst i) -> void
        def remember(known, i)
          v, addr = i.args
          at = slot(addr, i.offset)
          return known.clear unless at

          root, off = at
          width = Types::WIDTH.fetch(@types.fetch(v))
          ((off - 7)...(off + width)).each do |o|
            held = known[[root, o]]
            known.delete([root, o]) if held && o + held[1] > off
          end
          known[at] = [v, width]
        end

        # Whether the load reads all of a known store's value, with the same
        # type.
        #: (Hash[[String, Integer], [String, Integer]] known, Inst i) -> bool
        def forwarded?(known, i)
          at = slot(i.args[0], i.offset)
          return false unless at && (held = known[at])

          v, width = held
          return false unless Types::WIDTH.fetch(i.type) == width && @types.fetch(v) == i.type

          @rename[i.results[0]] = v
          true
        end
      end
    end
  end
end
