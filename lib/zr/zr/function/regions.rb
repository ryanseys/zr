# frozen_string_literal: true

require_relative "../../record"

module Zr
  module Zr
    class Function
      # `begin`/`rescue`/`else`/`ensure` and `retry`. A protected region
      # has a landing block of its own: a signal inside it lands there
      # instead of leaving the function. A rescue landing tests each
      # clause against the pending exception; an ensure landing runs the
      # ensure body with the signal set aside, then passes it on.
      module Regions
        # `slot` is the first of the record slots the region keeps its
        # values in: the value on the way out or the exception, the `$!`
        # the region replaced, and for an ensure the `$!` it began with.
        class Region < ::Zr::Record
          FIELDS = %i[landing ensure_body slot].freeze
          attr_accessor :landing, :ensure_body, :slot

          def initialize(landing = nil, ensure_body = nil, slot = nil)
            @landing = landing
            @ensure_body = ensure_body
            @slot = slot
          end

          def to_a = [@landing, @ensure_body, @slot]
        end

        private

        # The landing block a signal takes from here: the innermost
        # region's, or the function's own.
        def landing
          @regions.last&.landing || (@landing ||= @f.label)
        end

        def protect(node)
          return rescue_region(node) unless node.ensure_body

          with_ensure(node.ensure_body) { rescue_region(node) }
        end

        # The ensure body (a node, or a block of the lowering's own) runs
        # after the block's code on the normal way out, and in the
        # landing block on the signal's way out, where a raise shows as
        # `$!` meanwhile unless `errinfo` is false. An ensure body that
        # jumps away drops the raise, and `$!` goes back to what it was
        # when the region began, as ruby's does.
        def with_ensure(body, errinfo: true)
          region = Region.new(@f.label, body, reserve(errinfo ? 3 : 2))
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

        # The body under its rescue clauses, and the else arm after a
        # body that raised nothing.
        def rescue_region(node)
          return expr(node.body) if node.rescues.empty?

          region = Region.new(@f.label, nil, reserve(2))
          exc_at = value_offset(region.slot)
          prev_at = value_offset(region.slot + 1)
          head = @f.label
          merge, (result,) = @f.block(["i64"])
          # `$!` goes back to what it was here when a clause ends, not to
          # what an ensure on the way out left in it.
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
            # The clause that matched is where `:rescue` fires, so the
            # call stands here and not in `zr_rescue_enter`, which
            # `guarded` also uses to swallow a raise `defined?` made.
            # ruby names the clause's first statement and not the
            # `rescue` word, which is where its program counter lands.
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

        # The block's value, or nil when a raise leaves it: `defined?`
        # asks about a receiver this way.
        def guarded
          region = Region.new(@f.label, nil, reserve(1))
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
        # answered here; a miss falls through to the next test.
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

        # `retry`: `$!` back as it was, then the begin body again.
        def retry_region(node)
          @l.refuse(node, "retry outside a rescue clause is not lowered yet") if @retries.empty?
          head, prev_at, depth = @retries.last
          unwind(depth)
          kernel("zr_errinfo_set", @f.fetch("i64", @rec, prev_at))
          @f.jump(head)
          switch(@f.label, open: true)
          @qnil
        end

        # The ensure bodies between here and region depth `depth`,
        # innermost first: a `return` or a loop's jump runs them on its
        # way out.
        def unwind(depth)
          left = []
          while @regions.size > depth && !@f.terminated?
            region = @regions.pop
            left.unshift(region)
            run_ensure(region.ensure_body) if region.ensure_body
          end
          @regions.concat(left)
        end

        # `v` after the ensure bodies down to region depth `depth` ran,
        # kept in the record meanwhile.
        def through_ensures(v, depth = 0)
          return v if @regions.size <= depth

          at = value_offset(reserve(1))
          @f.store(v, @rec, at)
          unwind(depth)
          @sp -= 1
          # An ensure body that itself returned or jumped ended the block;
          # what follows is unreachable and goes in a block of its own.
          switch(@f.label, open: true) if @f.terminated?
          @f.fetch("i64", @rec, at)
        end

        # `n` fresh record slots; the scope's budget must cover them.
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
