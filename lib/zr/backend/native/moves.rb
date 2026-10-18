# frozen_string_literal: true

module Zr
  module Backend
    module Native
      # Moves between the places of values: the parallel copies of a
      # branch edge and of a function's parameters. A backend's Codegen
      # includes it, with `SCRATCH` (two registers that no value lives
      # in), `register?(x)`, `load_value`, `store_value`, `store_param`
      # and `value_in`, and an assembler `mov` between two registers.
      module Moves
        private

        # Parallel moves between registers and values. Each `[to, v]` of
        # `dests` gets the source at the same index of `srcs`. A source is a
        # value or a register, and `to` is a register or the value whose place
        # gets it. No destination is written while a pending copy reads it.
        # `SCRATCH[1]` breaks a cycle.
        #: (Array[[Registers::Register | Integer | String, String?]] dests, Array[String | Registers::Register] srcs) -> void
        def move_registers(dests, srcs)
          pending = {} #: Hash[Registers::Register | Integer | String, [String?, String | Registers::Register]]
          reads = Hash.new(0)
          dests.each_with_index do |(to, v), n|
            src = srcs[n]
            from = register?(src) ? src : place(src)
            next if to == from && (v.nil? || register?(src) || type_of(v) == type_of(src))

            pending[to] = [v, src]
            reads[from] += 1
          end
          ready = pending.keys.reject { |p| reads[p].positive? }
          loop do
            while (p = ready.pop)
              v, src = pending.delete(p) #: [String?, String | Registers::Register]
              move_register(p, v, src)
              from = register?(src) ? src : place(src)
              reads[from] -= 1
              ready << from if reads[from].zero? && pending.key?(from)
            end
            break if pending.empty?

            start = pending.keys.first
            v, src = pending.delete(start) #: [String?, String | Registers::Register]
            register?(src) ? @asm.mov(self.class::SCRATCH[1], src) : load_value(src, self.class::SCRATCH[1])
            at = register?(src) ? src : place(src)
            while at != start && pending.key?(at)
              d, s = pending.delete(at) #: [String?, String | Registers::Register]
              move_register(at, d, s)
              at = register?(s) ? s : place(s)
            end
            if v.nil?
              # A destination with no value is a register.
              reg = start #: Registers::Register
              @asm.mov(reg, self.class::SCRATCH[1])
            else
              store_value(v, self.class::SCRATCH[1])
            end
          end
        end

        # One move of `move_registers`: to the register `to`, or to the
        # home of the value `v`.
        #: (Registers::Register | Integer | String to, String? v, String | Registers::Register src) -> void
        def move_register(to, v, src)
          if v.nil?
            reg = to #: Registers::Register
            register?(src) ? @asm.mov(reg, src) : load_value(src, reg)
          elsif register?(src)
            store_param(v, src)
          else
            store_value(v, value_in(src, self.class::SCRATCH[0]))
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
        #: (String v) -> (Registers::Register | Integer | String)
        def place(v) = @reg[v] || @home.fetch(v) { unhomed(v) }

        # The place of a value that has no register and no home.
        #: (String v) -> (Registers::Register | String)
        def unhomed(v)
          return v if @remade.include?(v)
          return self.class::GATES if @pinned.include?(v)

          raise KeyError, v
        end

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
        #: (Array[String] dests, Array[String] srcs) -> void
        def parallel_copy(dests, srcs)
          pending = {} #: Hash[Registers::Register | Integer | String, [String, String]]
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
        # @rbs pending: Hash[Registers::Register | Integer | String, [String, String]]
        # @rbs reads: Hash[Registers::Register | Integer | String, Integer]
        # @rbs return: void
        def drain(pending, reads)
          ready = pending.keys.reject { |p| reads[p].positive? }
          while (p = ready.pop)
            d, s = pending.delete(p) #: [String, String]
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
        #: (Hash[Registers::Register | Integer | String, [String, String]] pending) -> void
        def break_cycle(pending)
          start = pending.keys.first
          held, source = pending.delete(start) #: [String, String]
          load_value(source, self.class::SCRATCH[1])
          at = place(source)
          while at != start
            d, s = pending.delete(at) #: [String, String]
            copy(d, s)
            at = place(s)
          end
          store_value(held, self.class::SCRATCH[1])
        end

        # Copies one value to the place of another. A source with a register
        # home is stored directly from it. Only a slot source needs a load,
        # which goes directly into the destination's register, if it has one.
        #: (String dest, String source) -> void
        def copy(dest, source)
          home = @reg[dest]
          return load_value(source, home) if home

          store_value(dest, value_in(source, self.class::SCRATCH[0]))
        end
      end
    end
  end
end
