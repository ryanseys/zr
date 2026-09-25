# frozen_string_literal: true

module Zr
  module Backend
    module Aarch64
      class Codegen
        # Moves between the places of values: the parallel copies of a
        # branch edge and of a function's parameters.

        private

        # Parallel moves between registers and values. Each `[to, v]` of
        # `dests` gets the source at the same index of `srcs`. A source is a
        # value or a register, and `to` is a register or the value whose place
        # gets it. No destination is written while a pending copy reads it.
        # `SCRATCH[1]` breaks a cycle.
        def move_registers(dests, srcs)
          pending = {}
          reads = Hash.new(0)
          dests.each_with_index do |(to, v), n|
            src = srcs[n]
            from = src.is_a?(Register) ? src : place(src)
            next if to == from && (v.nil? || src.is_a?(Register) || type_of(v) == type_of(src))

            pending[to] = [v, src]
            reads[from] += 1
          end
          ready = pending.keys.reject { |p| reads[p].positive? }
          loop do
            while (p = ready.pop)
              v, src = pending.delete(p)
              move_register(p, v, src)
              from = src.is_a?(Register) ? src : place(src)
              reads[from] -= 1
              ready << from if reads[from].zero? && pending.key?(from)
            end
            break if pending.empty?

            start = pending.keys.first
            v, src = pending.delete(start)
            src.is_a?(Register) ? @asm.mov(SCRATCH[1], src) : load_value(src, SCRATCH[1])
            at = src.is_a?(Register) ? src : place(src)
            while at != start && pending.key?(at)
              d, s = pending.delete(at)
              move_register(at, d, s)
              at = s.is_a?(Register) ? s : place(s)
            end
            v.nil? ? @asm.mov(start, SCRATCH[1]) : store_value(v, SCRATCH[1])
          end
        end

        # One move of `move_registers`: to the register `to`, or to the
        # home of the value `v`.
        def move_register(to, v, src)
          if v.nil?
            src.is_a?(Register) ? @asm.mov(to, src) : load_value(src, to)
          elsif src.is_a?(Register)
            store_param(v, src)
          else
            store_value(v, value_in(src, SCRATCH[0]))
          end
        end

        # The location of a value between instructions: the register from
        # the allocator, or the offset of its frame slot. Two values share a
        # place only when they share a register, because each slot has its
        # own offset.
        #
        # A Register or an Integer, with no tag. A Register compares by
        # identity and is never equal to a number, so the two kinds cannot
        # be confused. This runs several times for every edge in the program,
        # so it must not make an Array.
        #
        # A constant made at its reads has no place and is never a
        # destination. Its name is in place of a location, and no Register or
        # Integer is equal to it.
        def place(v) = @reg[v] || @home.fetch(v) { @remade.include?(v) ? v : @pinned.include?(v) ? Regalloc::GATES : raise(KeyError, v) }

        # The copies of an edge, in an order where no destination is written
        # while a source must still be read from it.
        #
        # An argument that is already in its parameter's place (for example a
        # loop variable that the back edge passes without change) needs no
        # instruction. Another argument needs one load, `mov` or store. A
        # temporary is necessary only for a real cycle, where two parameters
        # swap places.
        #
        # The saving is small: the allocator gives out ten registers, so most
        # arguments and parameters are in the frame, and a slot-to-slot copy
        # still costs a load and a store. The saving is on edges where one end
        # has a register.
        #
        # `SCRATCH[0]` contains one copy and is dead after it. `SCRATCH[1]`
        # contains the value that a broken cycle moved out, and is live until
        # the last copy of that cycle.
        def parallel_copy(dests, srcs)
          pending = {}
          reads = Hash.new(0)
          dests.each_with_index do |d, n|
            s = srcs[n]
            to = place(d)
            from = place(s)
            # Already in place. The types must also be the same: a place
            # contains a whole word, and a narrower value is read at its own width.
            next if to == from && type_of(d) == type_of(s)

            pending[to] = [d, s]
            reads[from] += 1
          end
          drain(pending, reads)
          break_cycle(pending) until pending.empty?
        end

        # Emits every copy whose destination no pending copy reads, then
        # every copy that this frees, until only cycles are left.
        def drain(pending, reads)
          ready = pending.keys.reject { |p| reads[p].positive? }
          while (p = ready.pop)
            d, s = pending.delete(p)
            copy(d, s)
            from = place(s)
            reads[from] -= 1
            ready << from if reads[from].zero? && pending.key?(from)
          end
        end

        # After `drain`, only cycles are left: every remaining destination is
        # still read, and a copy reads one place, so the remaining places map
        # one to one onto themselves.
        #
        # Move the source of one copy into a scratch register. Then the rest
        # of its cycle can be emitted in order.
        def break_cycle(pending)
          start = pending.keys.first
          held, source = pending.delete(start)
          load_value(source, SCRATCH[1])
          at = place(source)
          while at != start
            d, s = pending.delete(at)
            copy(d, s)
            at = place(s)
          end
          store_value(held, SCRATCH[1])
        end

        # Copies one value to the place of another. A source with a register
        # home is stored directly from it. Only a slot source needs a load.
        def copy(dest, source) = store_value(dest, value_in(source, SCRATCH[0]))
      end
    end
  end
end
