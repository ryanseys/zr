# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # `recv.each { |x| ... }` and `n.times { |i| ... }` run inline. The
      # loop is at the site, and the block's body is in the site's own
      # function. The block's locals are record slots of the site, and it
      # reads the scope's locals as the site does. The cost of a block
      # call (the descriptor, the builtin's frame, the yield, the block's
      # prologue and record) occurs once per loop, not once per iteration.
      #
      # The program sees the same behavior as the call. During the loop,
      # two frames are under the caller's (`zr_iter_enter`): the builtin's
      # and the block's, which gets the body's lines, so a backtrace is
      # the same. An unwind from the body goes to the site's own region,
      # which puts the caller's frame back on top, then continues the
      # unwind. The loop's end and a `break` also restore it. A `return`
      # leaves through the caller's epilogue, which unlinks everything.
      # `break` returns from the site, and `next` and `redo` act on the
      # loop, as in a `while`. The site tests the receiver once (an Array
      # or a fixnum, with the method's gate clear). All other receivers
      # use the normal call with the block descriptor.
      #
      # Only a block that passes `Scope.iterator_template?` runs this way:
      # at most one parameter, no inner block (its locals would need an
      # Env), no binding, no super, no def.
      module Iterators
        # The block's locals as record slots of the site's function. It
        # is used in place of the block's scope while its body lowers.
        class InlineScope
          attr_reader :raw_block

          def initialize(slots)
            @slots = slots
            # An inline scope is never a raw block's own scope, so this
            # never becomes anything else; kept nil rather than left
            # unset, for the same ivar shape as `Function#raw_block`.
            @raw_block = nil
          end

          def slot_index(node)
            @slots.fetch(node.name)
          end
        end

        private

        # Whether the site runs `node` inline.
        def iterator_template?(node)
          !traced? && !@l.internal? && Scope.iterator_template?(node)
        end

        # The send with its block: inline if the receiver permits it, else
        # as a call.
        def iterate(node, recv, argv, argc)
          fast = @f.label
          slow = @f.label
          merge, (result,) = @f.block(["i64"])
          case node.name
          when :each
            cell = @f.label
            array = @f.label
            other = @f.label
            ranged = @f.label
            @f.brif(@f.band(@f.icmp("eq", @f.band(recv, imm(7)), imm(0)), @f.icmp("ugt", recv, @qnil)), cell, slow)
            switch(cell)
            klass = @f.fetch("i64", recv, off(@l.layout("RBasic"), "klass"))
            @f.brif(@f.band(@f.icmp("eq", klass, global("G_ARRAY")), each_gate_clear("GATE_EACH")), array, other)
            switch(array)
            @f.jump(merge, [loop_in_place(node, recv, :array)])
            switch(other)
            @f.brif(@f.band(@f.icmp("eq", klass, global("G_RANGE")), each_gate_clear("GATE_RANGE_EACH")), ranged, slow)
            switch(ranged)
            # A Range of fixnums loops over its ends. Other ranges use the call.
            bounds = @f.stack_addr(@f.slot(16))
            @f.brif(kernel("zr_range_fix_bounds", recv, bounds), fast, slow)
            switch(fast)
            @f.jump(merge, [loop_in_place(node, recv, :range, bounds)])
          when :map, :select
            cell = @f.label
            @f.brif(@f.band(@f.icmp("eq", @f.band(recv, imm(7)), imm(0)), @f.icmp("ugt", recv, @qnil)), cell, slow)
            switch(cell)
            klass = @f.fetch("i64", recv, off(@l.layout("RBasic"), "klass"))
            gate = node.name == :map ? "GATE_MAP" : "GATE_SELECT"
            @f.brif(@f.band(@f.icmp("eq", klass, global("G_ARRAY")), gates_clear(gate)), fast, slow)
            switch(fast)
            @f.jump(merge, [loop_in_place(node, recv, :array)])
          when :upto
            # From one fixnum to another, Ruby's C counts with no send. The
            # loop is the one of a Range of fixnums, over these two ends.
            limit = @f.fetch("i64", argv)
            fix = @f.icmp("ne", @f.band(@f.band(recv, limit), imm(1)), imm(0))
            @f.brif(@f.band(fix, gates_clear("GATE_UPTO")), fast, slow)
            switch(fast)
            bounds = @f.stack_addr(@f.slot(16))
            @f.store(recv, bounds, 0)
            @f.store(limit, bounds, 8)
            @f.jump(merge, [loop_in_place(node, recv, :range, bounds)])
          when :times
            fix = @f.icmp("ne", @f.band(recv, imm(1)), imm(0))
            # <internal:numeric> counts with `<` and `succ`, so a program that
            # redefines either sends them from times as well.
            @f.brif(@f.band(fix, gates_clear("GATE_TIMES", "GATE_LT", "GATE_SUCC")), fast, slow)
            switch(fast)
            @f.jump(merge, [loop_in_place(node, recv, :times)])
          end
          switch(slow)
          @f.jump(merge, [call_with_block(node, recv, argv, argc)])
          switch(merge)
          result
        end

        # The loop. Link the two frames and reserve the block's locals
        # (then the index, a fixnum). Each iteration puts the next value
        # into the parameter's slot, sets the block's other locals to nil
        # as a call does, and runs the body. It reads an Array's length
        # again in each iteration, as `zr_ary_each` does. A Range's ends
        # are in `bounds`. Returns the receiver.
        def loop_in_place(node, recv, kind, bounds = nil)
          block = node.block
          frame = @l.layout("Frame")
          fn = @l.block(block, self)
          at_node(node)
          recs = @f.stack_addr(@f.slot(2 * frame.size))
          block_rec = @f.iadd(recs, imm(frame.size))
          kernel("zr_iter_enter", recs, recv, sym_word(node.name), @f.symbol_value(@f.symbol("zr_meta_#{fn}")))
          base = reserve(Scope.loop_slots(node))
          index_at = value_offset(base + block.locals.size)
          slots = block.locals.each_with_index.to_h { |name, i| [name, base + i] }
          param = block.params.required.first
          @f.store(kind == :range ? @f.fetch("i64", bounds, 0) : imm(1), @rec, index_at)
          # `map` and `select` make an Array as their builtins do (the
          # receiver's length, or 4), and push to it in the step.
          if %i[map select].include?(node.name)
            made_at = value_offset(base + block.locals.size + 1)
            @f.store(kernel("zr_ary_new", node.name == :map ? array_len(recv) : imm(4)), @rec, made_at)
            step, (got,) = @f.block(["i64"])
          end
          head = @f.label
          body = @f.label
          take = @f.label
          out = @f.label
          done, (value,) = @f.block(["i64"])
          loop = Loop.new(head: head, body: body, done: done, depth: @regions.size, step: step)
          @loops << loop
          unlink = Regions::Region.new(@f.cold(@f.label), nil, nil, [@inline_scope, @line_rec])
          @regions << unlink
          @f.jump(head)
          switch(head)
          i = @f.fetch("i64", @rec, index_at)
          case kind
          when :array then @f.brif(@f.icmp("slt", i, @f.bor(@f.ishl(array_len(recv), imm(1)), imm(1))), take, out)
          when :times then @f.brif(@f.icmp("slt", i, recv), take, out)
          when :range then @f.brif(@f.icmp("sle", i, @f.fetch("i64", bounds, 8)), take, out)
          end
          switch(take)
          @f.store(@f.iadd(i, imm(2)), @rec, index_at)
          if param
            v = kind == :array ? @f.fetch("i64", @f.iadd(array_ptr(recv), @f.ishl(@f.sshr(i, imm(1)), imm(3)))) : i
            @f.store(v, @rec, value_offset(slots.fetch(param)))
          end
          slots.each { |name, slot| @f.store(@qnil, @rec, value_offset(slot)) unless name == param }
          @f.jump(body)
          switch(body)
          saved = [@inline_scope, @line_rec, @line]
          @inline_scope = InlineScope.new(slots)
          @line_rec = block_rec
          @line = nil
          last = block.body ? expr(block.body) : @qnil
          unless @f.terminated?
            if step
              @f.jump(step, [last])
            else
              preempt
              @f.jump(head)
            end
          end
          @inline_scope, @line_rec, _ = saved
          @line = nil
          @regions.pop
          @loops.pop
          collect(node, recv, loop, got, base) if step
          switch(out)
          @f.jump(done, [step ? @f.fetch("i64", @rec, made_at) : recv])
          # An unwind from the body: put the caller's frame back on top,
          # then go to the outer landing block.
          switch(unlink.landing, open: true)
          @f.store(@rec, @task_addr, off(@task, "top"), region: :task)
          @f.jump(landing)
          switch(done)
          @f.store(@rec, @task_addr, off(@task, "top"), region: :task)
          release(base)
          value
        end

        # The step of an inline `map` or `select`: push the body's value
        # (`map`), or else, if the value is truthy, the element now at the
        # index (`select`; nil if the block shortened the Array, as
        # CRuby's rb_ary_elt gives), then go to the loop's head. The index
        # and the new Array are the slots above the block's locals at
        # `base` (`Scope.loop_slots`).
        def collect(node, recv, loop, got, base)
          switch(loop.step)
          index_at = value_offset(base + node.block.locals.size)
          made = @f.fetch("i64", @rec, value_offset(base + node.block.locals.size + 1))
          if node.name == :map
            kernel("zr_ary_push", made, got)
          else
            keep = @f.label
            onward = @f.label
            @f.brif(truthy(got), keep, onward)
            switch(keep)
            # The index slot already holds the next index, as a fixnum.
            at = @f.isub(@f.sshr(@f.fetch("i64", @rec, index_at), imm(1)), imm(1))
            kernel("zr_ary_push", made, kernel("zr_ary_at", recv, at))
            @f.jump(onward)
            switch(onward)
          end
          preempt
          @f.jump(loop.head)
        end
      end
    end
  end
end
