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

        # `node`, a test, as a branch: to `yes` when it is truthy, to
        # `no` when it is not. An `&&` or `||` branches on its left side
        # and asks its right side only when the left decided nothing;
        # the value it would have answered is never made, so a test of
        # several parts is a chain of branches with no join between.
        # A relation over plain reads branches on the comparison
        # (`Sends#relation_jump`). Anything else is tested as a value.
        def jump_if(node, yes, no)
          case node
          when Hir::And, Hir::Or
            rest = @f.label
            node.is_a?(Hir::And) ? jump_if(node.left, rest, no) : jump_if(node.left, yes, rest)
            switch(rest)
            jump_if(node.right, yes, no)
          else
            return relation_jump(node, yes, no) if relation_test?(node)

            v = expr(node)
            @f.brif(truthy(v), yes, no) unless @f.terminated?
          end
        end

        def branch(node)
          then_b = @f.label
          else_b = @f.label
          merge, (result,) = @f.block(["i64"])
          jump_if(node.cond, then_b, else_b)
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
        # The loop is entered before its condition, as compile.c does, so
        # a `break` or `next` in the condition belongs to this loop.
        def loop_while(node)
          head = @f.label
          body = @f.label
          out = @f.label
          done, (result,) = @f.block(["i64"])
          @loops << { head: head, body: body, done: done, depth: @regions.size }
          @f.jump(node.body_first ? body : head)
          switch(head)
          jump_if(node.cond, body, out)
          switch(out)
          @f.jump(done, [@qnil])
          switch(body)
          expr(node.body) if node.body
          @loops.pop
          unless @f.terminated?
            # The back edge is where a thread that only computes hands
            # the turn on; without it a spinner starves its siblings.
            preempt
            @f.jump(head)
          end
          switch(done)
          result
        end

        # A safe point (rt/kernel/send.rb): the poll word read, and the
        # kernel run only when it is set. Under wasm the count is the
        # clock, and one tick comes off it here.
        #
        # Not in the runtime's own Ruby. The scheduler and the waits are
        # written there, and a turn handed on from inside them is a
        # switch in the middle of a switch; its loops that run long are
        # the iterators, whose yields the kernel ticks.
        def preempt
          return if @l.internal?

          expired = @f.label
          go = @f.label
          if @l.wasm?
            count = static("preempt_count")
            n = @f.isub(@f.fetch("i64", count), imm(1))
            @f.store(n, count)
            @f.brif(@f.icmp("sle", n, imm(0)), expired, go)
          else
            @f.brif(@f.icmp("ne", @f.fetch("i64", static("current_task"), 8, region: :volatile), imm(0)), expired, go)
          end
          switch(expired)
          checked(kernel("zr_preempt_expired"))
          @f.jump(go)
          switch(go)
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
        # asks `value === subject` through a cell of its own, as any
        # receiver's method with no visibility rule (or is tested itself
        # when there is no subject), and the first truthy one's body
        # answers.
        def case_when(node)
          base = @sp
          subject_at = value_offset(reserve(1))
          @f.store(expr(node.subject), @rec, subject_at) if node.subject
          merge, (result,) = @f.block(["i64"])
          node.clauses.each do |values, body|
            hit = @f.label
            values.each do |value|
              miss = @f.label
              cond = if value.is_a?(Hir::Splat) && node.subject
                       at_node(value)
                       truthy(checked(kernel("zr_case_any", @f.fetch("i64", @rec, subject_at), expr(value.value))))
                     elsif value.is_a?(Hir::Splat)
                       at_node(value)
                       truthy(checked(kernel("zr_any_truthy", expr(value.value))))
                     elsif node.subject
                       staged([value, Hir::Slot.new(base, value.line)]) do |slots|
                         at_node(value)
                         match = Hir::Send.new(value, :===, [node.subject], value.line, false, false, nil, nil, false, false, nil)
                         truthy(checked(cached_send(match, @f.fetch("i64", slots), imm(1), @f.iadd(slots, imm(8)), @qnil, mode: 0)))
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
          parts = node.args + [node.kwargs].compact
          if parts.any?(Hir::Splat)
            slot = reserve(1)
            ary = gather(parts, slot)
            at_node(node)
            argc = array_len(ary)
            argc = kernel("zr_kw_argc", argc, array_ptr(ary)) if node.kwargs
            r = checked(block_call(argc, array_ptr(ary)))
            @sp = slot
            return r
          end

          staged(parts) do |argv|
            at_node(node)
            argc = imm(parts.size)
            argc = kernel("zr_kw_argc", argc, argv) if node.kwargs
            checked(block_call(argc, argv))
          end
        end

        # The block called as zr_yield calls it, at the site: the test
        # that there is one, then its function through the Proc. The
        # kernel's own yield polls for preemption first, which a
        # program's function does at its entry and at every back edge
        # -- the core's functions poll nowhere (`preempt`), so a core
        # iterator's `yield` keeps the kernel's, or `loop { }` would
        # never hand the turn on. No block given takes the kernel's road
        # too, which raises.
        def block_call(argc, argv)
          return kernel("zr_yield", @blk, argc, argv) if @l.internal?

          none = @f.label
          some = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.icmp("eq", @blk, @qnil), none, some)
          switch(none)
          @f.jump(merge, [kernel("zr_yield", @blk, argc, argv)])
          switch(some)
          fn = @f.fetch("i64", @blk, off(@proc_layout, "fn"))
          @f.jump(merge, [@f.call_indirect_val(@f.sig(ABI.fetch(:block), "i64"), fn, [@blk, argc, argv, @qnil])])
          switch(merge)
          result
        end

        # `return`: out of the method, or from a block through the runtime
        # to the method that made it.
        def return_from(node)
          v = expr(node.value)
          if @kind == :eval
            at_node(node)
            checked(kernel("zr_return_here", v))
          elsif @kind == :block
            unless_lambda(v) do
              at_node(node)
              checked(kernel("zr_return", @proc, v))
            end
          else
            leave(through_ensures(v), line: node.line)
          end
          @qnil
        end

        # zr_require's kinds; the eval road's own load is hidden from the
        # program.
        # `declared` is an autoload alone: the feature is held already, so
        # the name is declared and no row waits for a file.
        REQUIRE_KINDS = { require: 0, require_relative: 1, load: 2, eval_road: 3, computed: 4, declared: 5 }.freeze

        # A require of a file the program holds runs that file's toplevel,
        # once unless it is a load; a relative name with no file is a
        # LoadError.
        def require_unit(node)
          at_node(node)
          path = @f.symbol_value(@f.symbol(@l.literal(node.path)))
          return checked(kernel("zr_load_error", path, imm(node.path.bytesize))) unless node.unit

          fn = @f.func_addr(@f.callee(@l.unit_entry(node.unit), [], "i64"))
          checked(kernel("zr_require", kernel("zr_str_new", path, imm(node.path.bytesize)), fn, imm(REQUIRE_KINDS.fetch(node.kind))))
        end

        # `autoload :Name, "feature"`: the constant's row waits for the
        # unit, which its first read runs.
        # The receiver and the feature wait in record slots while the path
        # is made, whose allocation may collect.
        def autoload_unit(node)
          at_node(node)
          base = reserve(2)
          @f.store(node.recv ? expr(node.recv) : @self, @rec, value_offset(base))
          @f.store(kernel("zr_str_new", @f.symbol_value(@f.symbol(@l.literal(node.feature))), imm(node.feature.bytesize)), @rec, value_offset(base + 1))
          path = kernel("zr_str_new", @f.symbol_value(@f.symbol(@l.literal(node.path))), imm(node.path.bytesize))
          recv = @f.fetch("i64", @rec, value_offset(base))
          feature = @f.fetch("i64", @rec, value_offset(base + 1))
          fn = node.unit ? @f.func_addr(@f.callee(@l.unit_entry(node.unit), [], "i64")) : imm(0)
          kind = REQUIRE_KINDS.fetch(node.declared ? :declared : node.unit ? :require : :computed)
          result = checked(kernel("zr_autoload", recv, sym_word(node.name), feature, fn, @cref, imm(kind), path))
          release(base)
          result
        end

        # `redo`: the innermost loop's body again without its test, or the
        # block's body again with the parameters as they are.
        def redo_body(node)
          if (loop = @loops.last)
            through_ensures(@qnil, loop[:depth])
            preempt
            @f.jump(loop[:body])
          else
            @l.refuse(node, "redo outside a block or loop is not lowered yet") unless @kind == :block
            through_ensures(@qnil)
            preempt
            @f.jump(@body_label)
          end
          switch(@f.label, open: true)
          @qnil
        end

        # `break`/`next`: out of the innermost loop when one encloses the
        # statement, else out of the block.
        def jump_out(node, kind)
          v = expr(node.value)
          if (loop = @loops.last)
            v = through_ensures(v, loop[:depth])
            if kind == :break
              @f.jump(loop[:done], [v])
            else
              # A back edge like the one at the body's end.
              preempt
              @f.jump(loop[:head])
            end
            switch(@f.label, open: true)
            return @qnil
          end
          @l.refuse(node, "#{kind} outside a block or loop is not lowered yet") unless @kind == :block
          if kind == :next
            leave(through_ensures(v))
          else
            unless_lambda(v) do
              at_node(node)
              checked(kernel("zr_break", @proc, v))
            end
          end
          @qnil
        end
      end
    end
  end
end
