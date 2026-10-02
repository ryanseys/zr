# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # `begin`/`rescue`/`else`/`ensure` and `retry`. A protected region
      # has its own landing block: an unwind inside it goes there and does
      # not leave the function. A rescue landing tests each clause against
      # the pending exception. An ensure landing saves the pending unwind,
      # runs the ensure body, then continues the unwind.
      module Regions
        # `slot` is the first record slot for the region's values: the
        # exit value or the exception, the `$!` that the region replaced,
        # and for an ensure, the `$!` at its start. `outer` marks an inline
        # loop (Iterators): it holds the site's own inline scope and line
        # record, which the regions under it lower with.
        Region = Data.define(:landing, :ensure_body, :slot, :outer) do
          def initialize(landing:, ensure_body:, slot:, outer: nil) = super
        end

        private

        # The landing block for an unwind from here: the innermost
        # region's, or the function's own.
        def landing
          @regions.last&.landing || (@landing ||= @f.cold(@f.label))
        end

        def protect(node)
          return rescue_region(node) unless node.ensure_body

          with_ensure(node.ensure_body) { rescue_region(node) }
        end

        # The ensure body (a node, or a lowering block) runs after the
        # block's code on a normal exit. During an unwind, it runs in the
        # landing block, and a raise is visible as `$!` unless `errinfo`
        # is false. An ensure body that jumps out discards the raise, and
        # `$!` is restored to its value at the region's start, as in ruby.
        def with_ensure(body, errinfo: true)
          region = Region.new(@f.cold(@f.label), body, reserve(errinfo ? 3 : 2))
          value_at = value_offset(region.slot)
          prev_at = value_offset(region.slot + 1)
          began_at = value_offset(region.slot + 2)
          signal = @f.stack_addr(@f.slot(24))
          merge, (result,) = @f.block(["i64"])
          @f.store(kernel("zr_errinfo"), @rec, began_at) if errinfo
          @regions << region
          v = yield
          @regions.pop
          unless @f.terminated?
            @f.store(v, @rec, value_at)
            run_ensure(body)
            @f.jump(merge, [@f.fetch("i64", @rec, value_at)]) unless @f.terminated?
          end
          switch(region.landing, open: true)
          @f.store(kernel("zr_errinfo"), @rec, prev_at) if errinfo
          @f.store(kernel("zr_signal_take", signal), @rec, value_at)
          if errinfo
            dropped = -> { kernel("zr_errinfo_set", @f.fetch("i64", @rec, began_at)) }
            with_ensure(dropped, errinfo: false) { run_ensure(body) }
          else
            run_ensure(body)
          end
          unless @f.terminated?
            kernel("zr_errinfo_set", @f.fetch("i64", @rec, prev_at)) if errinfo
            kernel("zr_signal_restore", @f.fetch("i64", @rec, value_at), signal)
            @f.jump(landing)
          end
          switch(merge)
          @sp = region.slot
          result
        end

        def run_ensure(body)
          body.is_a?(Proc) ? body.call : expr(body)
        end

        # The body in its rescue clauses, and the else branch after a body
        # that raised nothing.
        def rescue_region(node)
          return expr(node.body) if node.rescues.empty?

          region = Region.new(@f.cold(@f.label), nil, reserve(2))
          exc_at = value_offset(region.slot)
          prev_at = value_offset(region.slot + 1)
          head = @f.label
          merge, (result,) = @f.block(["i64"])
          # When a clause ends, `$!` is restored to its value here, not to
          # the value that an ensure on the way out put in it.
          @f.store(kernel("zr_errinfo"), @rec, prev_at)
          @f.jump(head)
          switch(head)
          @regions << region
          v = expr(node.body)
          @regions.pop
          unless @f.terminated?
            v = expr(node.else_body) if node.else_body
            @f.jump(merge, [v]) unless @f.terminated?
          end

          switch(region.landing, open: true)
          exc = kernel("zr_rescuable")
          @f.store(exc, @rec, exc_at)
          clauses = @f.label
          @f.brif(@f.icmp("eq", exc, qundef), landing, clauses)
          switch(clauses)
          handlers = node.rescues.map { |clause| [rescue_test(clause, exc_at), clause] }
          @f.jump(landing)

          handlers.each do |handler, clause|
            switch(handler)
            kernel("zr_rescue_enter")
            # `:rescue` fires at the matched clause, so the call is here,
            # not in `zr_rescue_enter` (`guarded` also uses that to discard
            # a raise from `defined?`). Ruby reports the clause's first
            # statement, not the `rescue` keyword, because its program
            # counter goes there.
            kernel("zr_trace_rescue", imm((clause.body || clause).line))
            if clause.target
              prepared = clause.target.is_a?(Hir::Send) ? prepare(Hir::MultiTarget.new([clause.target], nil, [], clause.line)) : {}
              assign_target(clause.target, @f.fetch("i64", @rec, exc_at), prepared)
            end
            restore = -> { kernel("zr_errinfo_set", @f.fetch("i64", @rec, prev_at)) }
            v = with_ensure(restore, errinfo: false) do
              @retries << [head, prev_at, @regions.size]
              body = expr(clause.body)
              @retries.pop
              body
            end
            @f.jump(merge, [v]) unless @f.terminated?
          end
          switch(merge)
          @sp = region.slot
          result
        end

        # The block's value, or nil if a raise leaves it. `defined?` uses
        # this to test a receiver.
        def guarded
          region = Region.new(@f.cold(@f.label), nil, reserve(1))
          prev_at = value_offset(region.slot)
          merge, (result,) = @f.block(["i64"])
          @regions << region
          v = yield
          @regions.pop
          @f.jump(merge, [v]) unless @f.terminated?
          switch(region.landing, open: true)
          exc = kernel("zr_rescuable")
          give_up = @f.label
          @f.brif(@f.icmp("eq", exc, qundef), landing, give_up)
          switch(give_up)
          @f.store(kernel("zr_rescue_enter"), @rec, prev_at)
          kernel("zr_errinfo_set", @f.fetch("i64", @rec, prev_at))
          @f.jump(merge, [@qnil])
          switch(merge)
          @sp = region.slot
          result
        end

        # The tests for one clause, each a branch to the handler block
        # that this returns. A miss falls through to the next test.
        def rescue_test(clause, exc_at)
          handler = @f.label
          classes = clause.classes.empty? ? [nil] : clause.classes
          classes.each do |c|
            at_node(clause)
            matched = if c.is_a?(Hir::Splat)
                        checked(kernel("zr_exc_match_any", @f.fetch("i64", @rec, exc_at), expr(c.value)))
                      else
                        checked(kernel("zr_exc_match", @f.fetch("i64", @rec, exc_at), c ? expr(c) : global("G_STANDARD_ERROR")))
                      end
            miss = @f.label
            @f.brif(truthy(matched), handler, miss)
            switch(miss)
          end
          handler
        end

        # `retry`: restore `$!`, then run the begin body again.
        def retry_region(node)
          @l.unsupported(node, "retry outside a rescue clause") if @retries.empty?
          head, prev_at, depth = @retries.last
          unwind(depth)
          kernel("zr_errinfo_set", @f.fetch("i64", @rec, prev_at))
          @f.jump(head)
          switch(@f.label, open: true)
          @qnil
        end

        # The ensure bodies between here and region depth `depth`,
        # innermost first. A `return` or a loop's jump runs them when it
        # leaves.
        def unwind(depth)
          left = []
          inner = [@inline_scope, @line_rec]
          while @regions.size > depth && !@f.terminated?
            region = @regions.pop
            left.unshift(region)
            if region.outer
              leave_inline(region.outer) if @regions.size > depth
            elsif region.ensure_body
              run_ensure(region.ensure_body)
            end
          end
          @inline_scope, @line_rec = inner
          @line = nil
          @regions.concat(left)
        end

        # An unwind that goes on past an inline loop leaves the loop: the
        # caller's frame goes back on top, and the ensure bodies outside
        # the loop read the site's locals, not the block's.
        def leave_inline(outer)
          @f.store(@rec, @task_addr, off(@task, "top"), region: :task)
          @inline_scope, @line_rec = outer
          @line = nil
        end

        # Runs the ensure bodies down to region depth `depth`, then returns
        # `v`. The record keeps `v` during the ensure bodies.
        def through_ensures(v, depth = 0)
          return v if @regions.size <= depth

          at = value_offset(reserve(1))
          @f.store(v, @rec, at)
          unwind(depth)
          @sp -= 1
          # An ensure body that returned or jumped ended the block. The code
          # after it is unreachable and goes in a new block.
          switch(@f.label, open: true) if @f.terminated?
          @f.fetch("i64", @rec, at)
        end

        # Reserves `n` new record slots. The scope's slot count must
        # include them.
        def reserve(n)
          base = @sp
          @sp += n
          raise ArgumentError, "#{@name}: #{@sp} record slots used of the #{@nvalues} the scope counted" if @sp > @nvalues

          base
        end
      end
    end
  end
end
