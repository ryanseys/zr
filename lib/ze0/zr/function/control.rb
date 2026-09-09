# frozen_string_literal: true

module Ze0
  module Zr
    class Function
      # Branches, loops, short-circuit operators, and the jumps that leave
      # a block or a loop.
      module Control
        private

        # The condition a Value's truthiness gives: anything but nil and false.
        def truthy(v)
          @f.icmp("ne", @f.band(v, imm(-9)), imm(0))
        end

        def branch(node)
          cond = truthy(expr(node.cond))
          then_b = @f.label
          else_b = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(cond, then_b, else_b)
          switch(then_b)
          v = node.yes ? expr(node.yes) : @qnil
          @f.jump(merge, [v]) unless @f.terminated?
          switch(else_b, open: !@f.terminated?)
          v = node.no ? expr(node.no) : @qnil
          @f.jump(merge, [v]) unless @f.terminated?
          switch(merge)
          result
        end

        # `while`: nil when the condition ends it, else the `break` value.
        def loop_while(node)
          head = @f.label
          body = @f.label
          out = @f.label
          done, (result,) = @f.block(["i64"])
          @f.jump(head)
          switch(head)
          @f.brif(truthy(expr(node.cond)), body, out)
          switch(out)
          @f.jump(done, [@qnil])
          switch(body)
          @loops << { head: head, done: done, depth: @regions.size }
          expr(node.body) if node.body
          @loops.pop
          @f.jump(head) unless @f.terminated?
          switch(done)
          result
        end

        # `a && b` answers `a` when it is falsy, else `b`; `||` the reverse.
        def logical(node)
          left = expr(node.left)
          rest = @f.label
          skip = @f.label
          merge, (result,) = @f.block(["i64"])
          cond = truthy(left)
          node.is_a?(Hir::And) ? @f.brif(cond, rest, skip) : @f.brif(cond, skip, rest)
          switch(skip)
          @f.jump(merge, [left])
          switch(rest)
          right = expr(node.right)
          @f.jump(merge, [right]) unless @f.terminated?
          switch(merge)
          result
        end

        # `case`: the subject waits in a record slot; each `when` value
        # asks `value === subject` (or is tested itself when there is no
        # subject), and the first truthy one's body answers.
        def case_when(node)
          base = @sp
          subject_at = value_offset(reserve(1))
          @f.store(expr(node.subject), @rec, subject_at) if node.subject
          merge, (result,) = @f.block(["i64"])
          node.clauses.each do |values, body|
            hit = @f.label
            values.each do |value|
              miss = @f.label
              cond = if node.subject
                       staged([value, Hir::Slot.new(base, value.line)]) do |slots|
                         at_line(value.line)
                         truthy(checked(kernel("zr_send", @f.fetch("i64", slots), imm(sym_id(:===)), imm(1), @f.iadd(slots, imm(8)))))
                       end
                     else
                       truthy(expr(value))
                     end
              @f.brif(cond, hit, miss)
              switch(miss)
            end
            after = @f.label
            @f.jump(after)
            switch(hit)
            v = expr(body)
            @f.jump(merge, [v]) unless @f.terminated?
            switch(after)
          end
          v = node.else_body ? expr(node.else_body) : @qnil
          @f.jump(merge, [v]) unless @f.terminated?
          switch(merge)
          @sp = base
          result
        end

        def yield_block(node)
          if node.args.any?(Hir::Splat)
            slot = reserve(1)
            ary = gather(node.args, slot)
            at_line(node.line)
            r = checked(kernel("zr_yield", @blk, array_len(ary), array_ptr(ary)))
            @sp = slot
            return r
          end

          staged(node.args) do |argv|
            at_line(node.line)
            checked(kernel("zr_yield", @blk, imm(node.args.size), argv))
          end
        end

        # `return`: out of the method, or from a block through the runtime
        # to the method that made it.
        def return_from(node)
          v = expr(node.value)
          if @kind == :block
            unless_lambda(v) do
              at_line(node.line)
              checked(kernel("zr_return", @proc, v))
            end
          else
            leave(through_ensures(v))
          end
          @qnil
        end

        # `break`/`next`: out of the innermost loop when one encloses the
        # statement, else out of the block.
        def jump_out(node, kind)
          v = expr(node.value)
          if (loop = @loops.last)
            v = through_ensures(v, loop[:depth])
            kind == :break ? @f.jump(loop[:done], [v]) : @f.jump(loop[:head])
            switch(@f.label, open: true)
            return @qnil
          end
          @l.refuse(node, "#{kind} outside a block or loop is not lowered yet") unless @kind == :block
          if kind == :next
            leave(through_ensures(v))
          else
            unless_lambda(v) do
              at_line(node.line)
              checked(kernel("zr_break", @proc, v))
            end
          end
          @qnil
        end
      end
    end
  end
end
