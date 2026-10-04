# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # Multiple assignment and destructuring. The value becomes an Array
      # (through `to_ary` if it has one) in a record slot, and each target
      # gets its element. A nested target destructures its element again.
      # A send target (`h[k]`, `o.attr`) stages its receiver and arguments
      # before the value is evaluated, in CRuby's order.
      #
      # If the value of `a, b = x, y` is not used, no Array is made: the
      # elements go into slots and each target gets its own, as CRuby's
      # compiler does for a popped `masgn`. A rest target still gets an
      # Array of the remaining elements.
      module Targets
        # @type instance: Function
        # @rbs @cref: String
        # @rbs @f: IR::Function
        # @rbs @l: Lower
        # @rbs @name: String
        # @rbs @qnil: String
        # @rbs @rec: String
        # @rbs @self: String
        # @rbs @sp: Integer

        private

        #: (Hir::MultiAssign node) -> String
        def multi_assign(node)
          return spread_assign(node) if spread_assign?(node)

          base = @sp
          prepared = prepare(node.target)
          at = value_offset(reserve(1))
          @f.store(expr(node.value), @rec, at)
          destructure(node.target, @f.fetch("i64", @rec, at), prepared)
          value = @f.fetch("i64", @rec, at)
          @sp = base
          value
        end

        #: (Hir::MultiAssign node) -> bool
        def spread_assign?(node)
          value = node.value
          !node.taken && value.is_a?(Hir::ArrayLit) && value.elements.none?(Hir::Splat) && node.target.rights.empty?
        end

        #: (Hir::MultiAssign node) -> String
        def spread_assign(node)
          base = @sp
          target = node.target
          prepared = prepare(target)
          # `spread_assign?` found an ArrayLit.
          list = node.value #: Hir::ArrayLit
          elements = list.elements
          staged(elements) do |_, at|
            target.lefts.each_with_index do |t, i|
              assign_target(t, i < elements.size ? @f.fetch("i64", @rec, value_offset(at + i)) : @qnil, prepared)
            end
            rest = target.rest
            unless rest.nil? || rest.is_a?(Symbol)
              n = [elements.size - target.lefts.size, 0].max
              assign_target(rest, kernel("zr_ary_of", imm(n), @f.iadd(@rec, imm(value_offset(at + elements.size - n)))), prepared)
            end
          end
          @sp = base
          @qnil
        end

        # Stages the send targets' receivers and arguments into slots. Each
        # send gets a receiver slot, its argument slots, and a value slot.
        #: (Hir::MultiTarget target, ?Hash[Hir::node, Integer] prepared) -> Hash[Hir::node, Integer]
        def prepare(target, prepared = {})
          (target.lefts + [target.rest] + target.rights).each do |t|
            case t
            when Hir::Send
              # A splat collects the indexes into one Array next to the
              # receiver. The write adds the value to them.
              wide = t.args.any?(Hir::Splat)
              slot = reserve(wide ? 2 : 2 + t.args.size)
              @f.store(expr(t.recv), @rec, value_offset(slot))
              if wide
                gather(t.args, slot + 1)
              else
                t.args.each_with_index { |a, i| @f.store(expr(a), @rec, value_offset(slot + 1 + i)) }
              end
              prepared[t] = slot
            when Hir::ConstWrite
              # `a::B, c = value` evaluates `a` before the value, in CRuby's
              # order.
              scope = t.scope
              next if scope.nil? || scope.is_a?(Symbol)

              slot = reserve(1)
              @f.store(expr(scope), @rec, value_offset(slot))
              prepared[t] = slot
            when Hir::MultiTarget then prepare(t, prepared)
            end
          end
          prepared
        end

        #: (Hir::MultiTarget target, String value, Hash[Hir::node, Integer] prepared) -> void
        def destructure(target, value, prepared)
          at = value_offset(reserve(1))
          @f.store(checked(kernel("zr_masgn_ary", value)), @rec, at)
          ary = -> { @f.fetch("i64", @rec, at) }
          nl = imm(target.lefts.size)
          nr = imm(target.rights.size)
          target.lefts.each_with_index { |t, i| assign_target(t, kernel("zr_ary_at", ary.call, imm(i)), prepared) }
          rest = target.rest
          assign_target(rest, kernel("zr_masgn_rest", ary.call, nl, nr), prepared) unless rest.nil? || rest.is_a?(Symbol)
          target.rights.each_with_index { |t, i| assign_target(t, kernel("zr_masgn_right", ary.call, nl, nr, imm(i)), prepared) }
          @sp -= 1
        end

        # `recv[args] op= value`: the receiver and arguments are evaluated
        # once into slots, then `[]`, the operation, and `[]=` are sent.
        #: (Hir::IndexOpAssign node) -> String
        def index_op_assign(node)
          base = @sp
          slots = reserve(1 + node.args.size)
          @f.store(expr(node.recv), @rec, value_offset(slots))
          # A splat keeps its array in the slot and splats it at both
          # sends, so the indexes are evaluated once.
          node.args.each_with_index { |a, i| @f.store(expr(a.is_a?(Hir::Splat) ? a.value : a), @rec, value_offset(slots + 1 + i)) }
          recv = Hir::Slot.new(slots, node.line)
          # A literal `self` keeps its right to call private methods.
          recv = node.recv if node.recv.is_a?(Hir::SelfRef)
          args = node.args.each_with_index.map do |a, i|
            slot = Hir::Slot.new(slots + 1 + i, node.line)
            a.is_a?(Hir::Splat) ? Hir::Splat.new(slot, node.line) : slot
          end
          # The inline `[]` path checks visibility as an explicit call does,
          # so a literal `self` dispatches instead.
          opt = node.args.none?(Hir::Splat) && !node.recv.is_a?(Hir::SelfRef)
          read = @l.noted(Hir::Send.of(recv, :[], args, node.line, opt: opt, using: node.using), node)
          result = op_assign(node, read) { |v| @l.noted(Hir::Send.of(recv, :[]=, args + [v], node.line, opt: opt, using: node.using), node) }
          @sp = base
          result
        end

        # `recv.name op= value` likewise.
        #: (Hir::AttrOpAssign node) -> String
        def attr_op_assign(node)
          base = @sp
          slot = reserve(1)
          @f.store(expr(node.recv), @rec, value_offset(slot))
          recv = Hir::Slot.new(slot, node.line)
          # A literal `self` keeps its right to call private methods.
          recv = node.recv if node.recv.is_a?(Hir::SelfRef)
          read = @l.noted(Hir::Send.of(recv, node.name, [], node.line, using: node.using), node)
          write = ->(v) { @l.noted(Hir::Send.of(recv, :"#{node.name}=", [v], node.line, using: node.using), node) }
          result = if node.safe
                     unless_nil(@f.fetch("i64", @rec, value_offset(slot))) { op_assign(node, read, &write) }
                   else
                     op_assign(node, read, &write)
                   end
          @sp = base
          result
        end

        # The block's value, or nil without running it when `v` is nil.
        #: (String v) { () -> String } -> String
        def unless_nil(v)
          run = @f.label
          skip = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(@f.icmp("eq", v, @qnil), skip, run)
          switch(skip)
          @f.jump(merge, [@qnil])
          switch(run)
          got = yield
          @f.jump(merge, [got]) unless @f.terminated?
          switch(merge)
          result
        end

        # The current value read, the operation (`||=` and `&&=` short
        # circuit), and the write the block builds around the new value,
        # itself kept in a slot.
        #: (Hir::IndexOpAssign | Hir::AttrOpAssign node, Hir::Send read) { (Hir::Slot) -> Hir::Send } -> String
        def op_assign(node, read)
          slot = reserve(1)
          current_at = value_offset(slot)
          @f.store(expr(read), @rec, current_at)
          current = Hir::Slot.new(slot, node.line)
          case node.op
          when :or, :and
            keep = @f.label
            write = @f.label
            merge, (result,) = @f.block(["i64"]) #: [String, [String]]
            cond = truthy(@f.fetch("i64", @rec, current_at))
            node.op == :or ? @f.brif(cond, keep, write) : @f.brif(cond, write, keep)
            switch(keep)
            @f.jump(merge, [@f.fetch("i64", @rec, current_at)])
            switch(write)
            @f.store(expr(node.value), @rec, current_at)
            expr(yield(current))
            @f.jump(merge, [@f.fetch("i64", @rec, current_at)])
            switch(merge)
            result
          else
            @f.store(expr(@l.noted(Hir::Send.of(current, node.op, [node.value], node.line, using: node.using), node)), @rec, current_at)
            expr(yield(current))
            @f.fetch("i64", @rec, current_at)
          end
        end

        # `@name = v`: an inline store into the guessed ivar entry, else
        # the kernel's write, which raises for a frozen receiver at this
        # line.
        #: (Hir::IvarWrite node, String v) -> String
        def ivar_write(node, v)
          at_node(node)
          ivar = ivar_name(node.name)
          ic = cache("iv", "IvarCache")
          slow = @f.label
          done = @f.label
          row = guessed_ivar_row(ic, ivar, slow, writing: true) do |t, len|
            append_ivar_row(t, len, ivar, v)
            @f.jump(done)
          end
          @f.store(v, row, off(@l.layout("IvEntry"), "value"), region: :malloc)
          ivar_barrier(v)
          @f.jump(done)
          switch(slow)
          checked(kernel("zr_ivar_set_cached", @self, sym_word(ivar), v, ic))
          @f.jump(done)
          switch(done)
          v
        end

        # Appends an entry for `ivar` with `v` after the last entry of table
        # `t` (length `len`), and sets the name's bit in the table's names.
        #: (String t, String len, Symbol ivar, String v) -> void
        def append_ivar_row(t, len, ivar, v)
          table = @l.layout("IvTab")
          entry = @l.layout("IvEntry")
          row = @f.iadd(@f.fetch("i64", t, off(table, "rows")), @f.ishl(len, imm(Math.log2(entry.size).to_i)))
          @f.store(sym_word(ivar), row, off(entry, "id"), region: :malloc)
          @f.store(v, row, off(entry, "value"), region: :malloc)
          ivar_barrier(v)
          @f.store(@f.iadd(len, imm(1)), t, off(table, "len"), region: :malloc)
          @f.store(@f.bor(@f.fetch("i64", t, off(table, "names")), sym_bit(ivar)), t, off(table, "names"), region: :malloc)
        end

        #: (Hir::node target, String v, Hash[Hir::node, Integer] prepared) -> void
        def assign_target(target, v, prepared)
          case target
          when Hir::Assign then write_local(slot_at(target), target.depth, v, target.name)
          when Hir::IvarWrite then ivar_write(target, v)
          when Hir::GvarWrite then gvar_write(target, v)
          when Hir::CvarWrite
            at_node(target)
            checked(kernel("zr_cvar_set", @cref, sym_word(target.name), v))
          when Hir::ConstWrite
            scope = prepared.key?(target) ? @f.fetch("i64", @rec, value_offset(prepared[target])) : scope_class(target.scope)
            at_node(target)
            checked(kernel("zr_const_set", scope, sym_word(target.name), v))
          when Hir::MultiTarget then destructure(target, v, prepared)
          when Hir::Send
            slot = prepared.fetch(target)
            recv = @f.fetch("i64", @rec, value_offset(slot))
            # `rescue => o&.x` writes nothing when `o` is nil.
            return unless_nil(recv) { send_target(target, slot, recv, v) } if target.safe

            send_target(target, slot, recv, v)
          end
        end

        # The write a send target makes: its staged arguments, then `v`.
        #: (Hir::Send target, Integer slot, String recv, String v) -> String
        def send_target(target, slot, recv, v)
          if target.args.any?(Hir::Splat)
            ary = @f.fetch("i64", @rec, value_offset(slot + 1))
            kernel("zr_ary_push", ary, v)
            argc, argv = array_len(ary), array_ptr(ary)
          else
            @f.store(v, @rec, value_offset(slot + 1 + target.args.size))
            argc, argv = imm(target.args.size + 1), @f.iadd(@rec, imm(value_offset(slot + 1)))
          end
          at_node(target)
          # The site's form counts the value too: the cell's shapes, its
          # direct entry and the inline Array path read the argument count
          # from the node, and `a[0, 2], b = ...` writes a range, not the
          # element `a[0]`.
          site = target.dup
          site.args = target.args + [Hir::Literal.new(nil, target.line)]
          return checked(opt_send(site, recv, argc, argv)) if target.opt

          # An explicit receiver cannot call a private writer. `self` can.
          checked(cached_send(site, recv, argc, argv, @qnil))
        end
      end
    end
  end
end
