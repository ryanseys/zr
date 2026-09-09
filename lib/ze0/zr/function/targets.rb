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
              slot = reserve(2 + t.args.size)
              @f.store(expr(t.recv), @rec, value_offset(slot))
              t.args.each_with_index { |a, i| @f.store(expr(a), @rec, value_offset(slot + 1 + i)) }
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

        def assign_target(target, v, prepared)
          case target
          when Hir::Assign then write_local(slot_at(target), target.depth, v)
          when Hir::IvarWrite then kernel("zr_ivar_set", @self, imm(sym_id(target.name)), v)
          when Hir::MultiTarget then destructure(target, v, prepared)
          when Hir::Send
            slot = prepared.fetch(target)
            @f.store(v, @rec, value_offset(slot + 1 + target.args.size))
            recv = @f.fetch("i64", @rec, value_offset(slot))
            argv = @f.iadd(@rec, imm(value_offset(slot + 1)))
            at_line(target.line)
            checked(kernel(target.opt ? "zr_opt_aset" : "zr_send", recv, imm(sym_id(target.name)), imm(target.args.size + 1), argv))
          end
        end
      end
    end
  end
end
