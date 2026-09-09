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
          @f.switch(then_b)
          v = node.yes ? expr(node.yes) : @qnil
          @f.jump(merge, [v]) unless @f.terminated?
          @f.switch(else_b, open: !@f.terminated?)
          v = node.no ? expr(node.no) : @qnil
          @f.jump(merge, [v]) unless @f.terminated?
          @f.switch(merge)
          result
        end

        def loop_while(node)
          head = @f.label
          body = @f.label
          done = @f.label
          @f.jump(head)
          @f.switch(head)
          @f.brif(truthy(expr(node.cond)), body, done)
          @f.switch(body)
          @loops << { head: head, done: done }
          expr(node.body) if node.body
          @loops.pop
          @f.jump(head) unless @f.terminated?
          @f.switch(done)
          @qnil
        end

        # `a && b` answers `a` when it is falsy, else `b`; `||` the reverse.
        def logical(node)
          left = expr(node.left)
          rest = @f.label
          skip = @f.label
          merge, (result,) = @f.block(["i64"])
          cond = truthy(left)
          node.is_a?(Hir::And) ? @f.brif(cond, rest, skip) : @f.brif(cond, skip, rest)
          @f.switch(skip)
          @f.jump(merge, [left])
          @f.switch(rest)
          right = expr(node.right)
          @f.jump(merge, [right]) unless @f.terminated?
          @f.switch(merge)
          result
        end

        def yield_block(node)
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
            at_line(node.line)
            checked(kernel("zr_return", @proc, v))
          else
            leave(v)
          end
          @qnil
        end

        # `break`/`next`: out of the innermost loop when one encloses the
        # statement, else out of the block.
        def jump_out(node, kind)
          v = expr(node.value)
          if (loop = @loops.last)
            @f.jump(kind == :break ? loop[:done] : loop[:head])
            @f.switch(@f.label, open: true)
            return @qnil
          end
          @l.refuse(node, "#{kind} outside a block or loop is not lowered yet") unless @kind == :block
          if kind == :next
            leave(v)
          else
            at_line(node.line)
            checked(kernel("zr_break", @proc, v))
          end
          @qnil
        end
      end
    end
  end
end
