# frozen_string_literal: true

module Ze0
  module Zr
    class Function
      # Multiple assignment and destructuring: the value becomes an Array
      # (`to_ary` when it has one) kept in a record slot, and each target
      # takes its element; a nested target takes its element apart again.
      # A target that is a send (`h[k]`, `o.attr`) stages its receiver
      # and arguments before the value is evaluated, as CRuby orders it.
      module Targets
        private

        def multi_assign(node)
          base = @sp
          prepared = prepare(node.target)
          at = value_offset(reserve(1))
          @f.store(expr(node.value), @rec, at)
          destructure(node.target, @f.fetch("i64", @rec, at), prepared)
          value = @f.fetch("i64", @rec, at)
          @sp = base
          value
        end

        # The send targets' receivers and arguments into slots: each
        # send gets a receiver slot, its arguments, and one for the value.
        def prepare(target, prepared = {})
          (target.lefts + [target.rest] + target.rights).each do |t|
            case t
            when Hir::Send
              # A splat gathers the indexes into one Array beside the
              # receiver; the value joins them at the write.
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
              # `a::B, c = value` asks for `a` before the value, as CRuby
              # orders it.
              next if t.scope.nil? || t.scope == :top

              slot = reserve(1)
              @f.store(expr(t.scope), @rec, value_offset(slot))
              prepared[t] = slot
            when Hir::MultiTarget then prepare(t, prepared)
            end
          end
          prepared
        end

        def destructure(target, value, prepared)
          at = value_offset(reserve(1))
          @f.store(checked(kernel("zr_masgn_ary", value)), @rec, at)
          ary = -> { @f.fetch("i64", @rec, at) }
          nl = imm(target.lefts.size)
          nr = imm(target.rights.size)
          target.lefts.each_with_index { |t, i| assign_target(t, kernel("zr_ary_at", ary.call, imm(i)), prepared) }
          assign_target(target.rest, kernel("zr_masgn_rest", ary.call, nl, nr), prepared) if target.rest && target.rest != :implicit
          target.rights.each_with_index { |t, i| assign_target(t, kernel("zr_masgn_right", ary.call, nl, nr, imm(i)), prepared) }
          @sp -= 1
        end

        # `recv[args] op= value`: receiver and arguments evaluated once
        # into slots, then `[]`, the operation, and `[]=` as sends.
        def index_op_assign(node)
          base = @sp
          slots = reserve(1 + node.args.size)
          @f.store(expr(node.recv), @rec, value_offset(slots))
          # A splat holds its array in the slot and splats it at both
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
          read = @l.noted(Hir::Send.new(recv, :[], args, node.line, false, opt, nil, nil, false), node)
          result = op_assign(node, read) { |v| @l.noted(Hir::Send.new(recv, :[]=, args + [v], node.line, false, opt, nil, nil, false), node) }
          @sp = base
          result
        end

        # `recv.name op= value` likewise.
        def attr_op_assign(node)
          base = @sp
          slot = reserve(1)
          @f.store(expr(node.recv), @rec, value_offset(slot))
          recv = Hir::Slot.new(slot, node.line)
          # A literal `self` keeps its right to call private methods.
          recv = node.recv if node.recv.is_a?(Hir::SelfRef)
          read = @l.noted(Hir::Send.new(recv, node.name, [], node.line, false, false, nil, nil, false), node)
          write = ->(v) { @l.noted(Hir::Send.new(recv, :"#{node.name}=", [v], node.line, false, false, nil, nil, false), node) }
          result = if node.safe
                     unless_nil(@f.fetch("i64", @rec, value_offset(slot))) { op_assign(node, read, &write) }
                   else
                     op_assign(node, read, &write)
                   end
          @sp = base
          result
        end

        # The block's value, or nil without running it when `v` is nil.
        def unless_nil(v)
          run = @f.label
          skip = @f.label
          merge, (result,) = @f.block(["i64"])
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
        def op_assign(node, read)
          slot = reserve(1)
          current_at = value_offset(slot)
          @f.store(expr(read), @rec, current_at)
          current = Hir::Slot.new(slot, node.line)
          case node.op
          when :or, :and
            keep = @f.label
            write = @f.label
            merge, (result,) = @f.block(["i64"])
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
            @f.store(expr(@l.noted(Hir::Send.new(current, node.op, [node.value], node.line, false, false, nil, nil, false), node)), @rec, current_at)
            expr(yield(current))
            @f.fetch("i64", @rec, current_at)
          end
        end

        # `@name = v`: a store into the guessed row inline; else the
        # kernel's write, which a frozen receiver refuses at this line.
        def ivar_write(node, v)
          at_node(node)
          id = sym_id(ivar_name(node.name))
          ic = cache("iv", "IvarCache")
          slow = @f.label
          done = @f.label
          row = guessed_ivar_row(ic, id, slow, writing: true)
          @f.store(v, row, off(@l.layout("IvEntry"), "value"))
          @f.jump(done)
          switch(slow)
          checked(kernel("zr_ivar_set_cached", @self, imm(id), v, ic))
          @f.jump(done)
          switch(done)
          v
        end

        def assign_target(target, v, prepared)
          case target
          when Hir::Assign then write_local(slot_at(target), target.depth, v, target.name)
          when Hir::IvarWrite then ivar_write(target, v)
          when Hir::GvarWrite then gvar_write(target, v)
          when Hir::CvarWrite
            at_node(target)
            checked(kernel("zr_cvar_set", @cref, imm(sym_id(target.name)), v))
          when Hir::ConstWrite
            scope = prepared.key?(target) ? @f.fetch("i64", @rec, value_offset(prepared[target])) : scope_class(target.scope)
            at_node(target)
            checked(kernel("zr_const_set", scope, imm(sym_id(target.name)), v))
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
          return checked(kernel("zr_opt_aset", recv, imm(sym_id(target.name)), argc, argv, imm(send_mode(target)))) if target.opt

          # An explicit receiver may not reach a private writer; `self` may.
          checked(kernel("zr_send_cached", cache("ic", "CallCache"), recv, imm(sym_id(target.name)), argc, argv, @qnil, imm(send_mode(target))))
        end
      end
    end
  end
end
