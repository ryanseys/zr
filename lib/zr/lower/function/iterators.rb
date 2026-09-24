# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # `recv.each { |x| ... }` and `n.times { |i| ... }` run in place:
      # the loop at the site, and the block's body in the site's own
      # function, where its locals are record slots of the site's and
      # the scope's locals are read as the site reads them. What a
      # block call cost -- the descriptor, the builtin's frame, the
      # yield, the block's prologue and its record -- goes once a loop
      # instead of once a turn.
      #
      # What a program sees is what the call gave it. Two frames stand
      # under the caller's for the loop's duration (`zr_iter_enter`):
      # the builtin's and the block's, which is where the body's lines
      # go, so a backtrace from inside reads as before. A signal from
      # the body lands in a region of the site's own, which puts the
      # caller's frame back on top before passing the signal on; the
      # loop's end and a `break` put it back too, and a `return` leaves
      # through the caller's epilogue, which unlinks everything. `break`
      # answers the site, `next` and `redo` are the loop's own, as in a
      # `while`. The receiver is tested once at the site -- an Array, or
      # a fixnum, with the method's gate clear -- and anything else takes
      # the call with the block descriptor as before.
      #
      # Only a block `Scope.iterator_template?` takes is run this way:
      # a parameter at most, no block of its own inside (its locals
      # would need an Env of the block's), no binding, no super, no def.
      module Iterators
        # The block's locals as record slots of the site's function,
        # standing where the block's scope stands while its body lowers.
        class InlineScope
          attr_reader :raw_block

          def initialize(slots)
            @slots = slots
          end

          def slot_index(node)
            @slots.fetch(node.name)
          end
        end

        private

        # Whether the site runs `node` in place.
        def iterator_template?(node)
          !traced? && !@l.internal? && Scope.iterator_template?(node)
        end

        # The send with its block, in place when the receiver allows it,
        # else as a call.
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
            @f.brif(@f.band(@f.icmp("eq", klass, global("G_ARRAY")), gate_clear("GATE_EACH")), array, other)
            switch(array)
            @f.jump(merge, [loop_in_place(node, recv, :array)])
            switch(other)
            @f.brif(@f.band(@f.icmp("eq", klass, global("G_RANGE")), gate_clear("GATE_RANGE_EACH")), ranged, slow)
            switch(ranged)
            # A Range of fixnums walks its ends; any other takes the call.
            bounds = @f.stack_addr(@f.slot(16))
            @f.brif(kernel("zr_range_fix_bounds", recv, bounds), fast, slow)
            switch(fast)
            @f.jump(merge, [loop_in_place(node, recv, :range, bounds)])
          when :times
            fix = @f.icmp("ne", @f.band(recv, imm(1)), imm(0))
            @f.brif(@f.band(fix, gate_clear("GATE_TIMES")), fast, slow)
            switch(fast)
            @f.jump(merge, [loop_in_place(node, recv, :times)])
          end
          switch(slow)
          @f.jump(merge, [call_with_block(node, recv, argv, argc)])
          switch(merge)
          result
        end

        # The loop: the two frames linked, the block's locals reserved
        # (the index after them, a fixnum), then each turn takes the next
        # value into the parameter's slot, nils the block's other locals
        # as a call would, and runs the body. An Array's length is read
        # again each turn, as `zr_ary_each` reads it; a Range's ends are
        # in `bounds`. The receiver is the answer.
        def loop_in_place(node, recv, kind, bounds = nil)
          block = node.block
          frame = @l.layout("Frame")
          fn = @l.block(block, self)
          at_node(node)
          recs = @f.stack_addr(@f.slot(2 * frame.size))
          block_rec = @f.iadd(recs, imm(frame.size))
          kernel("zr_iter_enter", recs, recv, sym_word(node.name), @f.symbol_value(@f.symbol("zr_meta_#{fn}")))
          base = reserve(block.locals.size + 1)
          index_at = value_offset(base + block.locals.size)
          slots = block.locals.each_with_index.to_h { |name, i| [name, base + i] }
          param = block.params.required.first
          @f.store(kind == :range ? @f.fetch("i64", bounds, 0) : imm(1), @rec, index_at)
          head = @f.label
          body = @f.label
          take = @f.label
          out = @f.label
          done, (value,) = @f.block(["i64"])
          @loops << { head: head, body: body, done: done, depth: @regions.size }
          unlink = Regions::Region.new(@f.label, nil, nil)
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
          expr(block.body) if block.body
          unless @f.terminated?
            preempt
            @f.jump(head)
          end
          @inline_scope, @line_rec, _ = saved
          @line = nil
          @regions.pop
          @loops.pop
          switch(out)
          @f.jump(done, [recv])
          # A signal from the body: the caller's frame back on top, then
          # the landing outside.
          switch(unlink.landing, open: true)
          @f.store(@rec, @task_addr, off(@task, "top"), region: :task)
          @f.jump(landing)
          switch(done)
          @f.store(@rec, @task_addr, off(@task, "top"), region: :task)
          release(base)
          value
        end
      end
    end
  end
end
