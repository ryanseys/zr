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
        # @type instance: Function
        # @rbs @f: IR::Function
        # @rbs @inline_scope: Iterators::InlineScope?
        # @rbs @l: Lower
        # @rbs @landing: String?
        # @rbs @line: Integer?
        # @rbs @line_rec: String?
        # @rbs @name: String
        # @rbs @nvalues: Integer
        # @rbs @qnil: String
        # @rbs @rec: String
        # @rbs @regions: Array[Regions::Region]
        # @rbs @ensure_path: Symbol
        # @rbs @jump_line: Integer?
        # @rbs @retries: Array[[String, Integer, Integer]]
        # @rbs @rescue_lines: Array[Integer]
        # @rbs @sp: Integer
        # @rbs @task: Machine::Layout
        # @rbs @task_addr: String

        # `slot` is the first record slot for the region's values: the
        # exit value or the exception, the `$!` that the region replaced,
        # and for an ensure, the `$!` at its start. `outer` marks an inline
        # loop (Iterators): it holds the site's own inline scope and line
        # record, which the regions under it lower with.
        #
        # The record's fields are typed in sig/zr/lower/function/regions.rbs.
        # @rbs skip
        Region = Data.define(:landing, :ensure_body, :slot, :outer)

        # The methods are in a reopened class, not in the block of
        # `Data.define`, so that the type check sees them in their class.
        class Region
          #: (landing: String, ensure_body: ensure_body?, slot: Integer?, ?outer: [Iterators::InlineScope?, String?]?) -> void
          def initialize(landing:, ensure_body:, slot:, outer: nil) = super
        end

        private

        # The landing block for an unwind from here: the innermost
        # region's, or the function's own.
        #: () -> String
        def landing
          region = @regions.last
          return region.landing if region

          @landing ||= @f.cold(@f.label)
        end

        #: (Hir::Begin node) -> String
        def protect(node)
          return rescue_region(node) unless node.ensure_body

          with_ensure(node.ensure_body) { rescue_region(node) }
        end

        # The ensure body (a node, or a lowering block) runs after the
        # block's code on a normal exit. During an unwind, it runs in the
        # landing block, and a raise is visible as `$!` unless `errinfo`
        # is false. An ensure body that jumps out discards the raise, and
        # `$!` is restored to its value at the region's start, as in ruby.
        #: (ensure_body body, ?errinfo: bool) { () -> String } -> String
        def with_ensure(body, errinfo: true)
          region = Region.new(@f.cold(@f.label), body, reserve(errinfo ? 3 : 2))
          value_at = value_offset(region.slot)
          prev_at = value_offset(region.slot + 1)
          began_at = value_offset(region.slot + 2)
          signal = @f.stack_addr(@f.slot(24))
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          @f.store(kernel("zr_errinfo"), @rec, began_at) if errinfo
          @regions << region
          v = yield
          @regions.pop
          unless @f.terminated?
            @f.store(v, @rec, value_at)
            run_ensure(body, :exit)
            @f.jump(merge, [@f.fetch("i64", @rec, value_at)]) unless @f.terminated?
          end
          switch(region.landing, open: true)
          @f.store(kernel("zr_errinfo"), @rec, prev_at) if errinfo
          # A written ensure (errinfo) raises a fatal unwind again as a raise.
          @f.store(kernel(errinfo ? "zr_ensure_take" : "zr_signal_take", signal), @rec, value_at)
          if errinfo
            dropped = -> { kernel("zr_errinfo_set", @f.fetch("i64", @rec, began_at)) }
            with_ensure(dropped, errinfo: false) { run_ensure(body, :raise) }
          else
            run_ensure(body, :raise)
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

        # Runs an ensure body on `path`: the normal exit (:exit), a raise
        # (:raise), or a local jump out of the region (:jump), whose own
        # instruction is on `jump_line`. A silent body's :line event
        # depends on them (`Hir::Trace#line_on`).
        #: (ensure_body body, ?Symbol path, ?Integer? jump_line) -> String
        def run_ensure(body, path = :jump, jump_line = nil)
          return body.call if body.is_a?(Proc)

          path_was = @ensure_path
          line_was = @jump_line
          @ensure_path = path
          @jump_line = jump_line
          begin
            expr(body)
          ensure
            @ensure_path = path_was
            @jump_line = line_was
          end
        end

        # The body in its rescue clauses, and the else branch after a body
        # that raised nothing.
        #: (Hir::Begin node) -> String
        def rescue_region(node)
          return expr(node.body) if node.rescues.empty?

          region = Region.new(@f.cold(@f.label), nil, reserve(2))
          exc_at = value_offset(region.slot)
          prev_at = value_offset(region.slot + 1)
          head = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
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
          # The clauses' classes are read with the raise as `$!`, so a
          # raise there has it as its cause.
          kernel("zr_errinfo_set", exc)
          handlers = node.rescues.map do |clause|
            [rescue_test(clause, exc_at), clause] #: [String, Hir::Rescue]
          end
          kernel("zr_errinfo_set", @f.fetch("i64", @rec, prev_at))
          kernel("zr_rescue_miss", @f.fetch("i64", @rec, exc_at))
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
            target = clause.target
            if target
              prepared = target.is_a?(Hir::Send) ? prepare(Hir::MultiTarget.new([target], nil, [], clause.line)) : {} #: Hash[Hir::node, Integer]
              assign_target(target, @f.fetch("i64", @rec, exc_at), prepared)
            end
            restore = -> { kernel("zr_errinfo_set", @f.fetch("i64", @rec, prev_at)) }
            v = with_ensure(restore, errinfo: false) do
              @retries << [head, prev_at, @regions.size]
              # CRuby runs a clause in a frame of its own, whose caller is
              # the scope at the `begin` line (Lower#rescues_table).
              @rescue_lines << node.line
              body = expr(clause.body)
              @rescue_lines.pop
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
        #: () { () -> String } -> String
        def guarded
          region = Region.new(@f.cold(@f.label), nil, reserve(1))
          prev_at = value_offset(region.slot)
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
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
        #: (Hir::Rescue clause, Integer exc_at) -> String
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
        #: (Hir::Retry node) -> String
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
        # leaves, from its instruction on `line`.
        #: (Integer depth, ?Integer? line) -> void
        def unwind(depth, line = nil)
          left = [] #: Array[Region]
          inner_scope = @inline_scope
          inner_rec = @line_rec
          while @regions.size > depth && !@f.terminated?
            region = @regions.pop #: Region
            left.unshift(region)
            outer = region.outer
            body = region.ensure_body
            if outer
              leave_inline(outer) if @regions.size > depth
            elsif body
              run_ensure(body, :jump, line)
            end
          end
          @inline_scope = inner_scope
          @line_rec = inner_rec
          @line = nil
          @regions.concat(left)
        end

        # An unwind that goes on past an inline loop leaves the loop: the
        # caller's frame goes back on top, and the ensure bodies outside
        # the loop read the site's locals, not the block's.
        #: ([Iterators::InlineScope?, String?] outer) -> void
        def leave_inline(outer)
          @f.store(@rec, @task_addr, off(@task, "top"), region: :task)
          @inline_scope, @line_rec = outer
          @line = nil
        end

        # Runs the ensure bodies down to region depth `depth`, then returns
        # `v`. The record keeps `v` during the ensure bodies. `line` is the
        # line of the jump that leaves.
        #: (String v, ?Integer depth, ?line: Integer?) -> String
        def through_ensures(v, depth = 0, line: nil)
          return v if @regions.size <= depth

          at = value_offset(reserve(1))
          @f.store(v, @rec, at)
          unwind(depth, line)
          @sp -= 1
          # An ensure body that returned or jumped ended the block. The code
          # after it is unreachable and goes in a new block.
          switch(@f.label, open: true) if @f.terminated?
          @f.fetch("i64", @rec, at)
        end

        # Reserves `n` new record slots. The scope's slot count must
        # include them.
        #: (Integer n) -> Integer
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
