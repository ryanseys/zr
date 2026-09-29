# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # Branches, loops, short-circuit operators, and the jumps that leave
      # a block or a loop.
      module Control
        private

        # The condition a Value's truthiness gives: anything but nil and false.
        def truthy(v)
          @f.icmp("ne", @f.band(v, imm(-9)), imm(0))
        end

        # Lowers the test `node` as a branch: to `yes` if it is truthy,
        # else to `no`. An `&&` or `||` branches on its left side, and
        # evaluates its right side only if the left side does not decide.
        # Its value is never made, so a test with several parts is a chain
        # of branches with no join. A comparison of plain reads branches
        # on the comparison (`Sends#relation_jump`). All other nodes are
        # tested as values.
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
            # A thread that only computes yields to the scheduler at the
            # back edge. Without this, a busy loop starves other threads.
            preempt
            @f.jump(head)
          end
          switch(done)
          result
        end

        # A safe point (runtime/kernel/send.rb): read the poll word, and
        # call the kernel only if it is set. Under wasm, the count is the
        # clock, and this subtracts one tick.
        #
        # Not in the runtime's own Ruby. The scheduler and the waits are
        # written there, and a yield from inside them would be a switch
        # during a switch. The runtime's long loops are the iterators, and
        # the kernel counts ticks at their yields.
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

        # `a && b` returns `a` if it is falsy, else `b`. `||` is the reverse.
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

        # `case`: the subject stays in a record slot. Each `when` value
        # sends `value === subject` through its own cell, with no
        # visibility check (or, with no subject, the value itself is
        # tested). The body of the first truthy one gives the result.
        def case_when(node)
          return class_case(node) if class_case?(node)

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
                         match = Hir::Send.of(value, :===, [node.subject], value.line)
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

        # The fewest `when` values for which a `case` gets a table. With
        # fewer, the chain's inline class tests cost less than the probe.
        CLASS_CASE_MIN = 6

        # Whether a `case` gets a table from the subject's class to its
        # arm (`class_case`): it has a subject, each `when` value is a
        # constant path (`A`, `::A`, `A::B`, with no other expression in
        # it), and it has at least CLASS_CASE_MIN of them. A traced
        # program keeps the chain, so each `===` gives its events.
        def class_case?(node)
          return false if node.subject.nil? || traced?

          values = node.clauses.flat_map(&:first)
          values.size >= CLASS_CASE_MIN && values.all? { |v| constant_path?(v) }
        end

        def constant_path?(node)
          node.is_a?(Hir::ConstRead) && (node.scope.nil? || node.scope == :top || constant_path?(node.scope))
        end

        # A `case` on class arms, in constant time for a subject class that
        # the site saw before. The site's cache entry (CaseCache,
        # runtime/kernel/cache.rb) has a table from a class to an arm. If
        # the entry is valid for this cref and the two stamps, and the
        # subject's class has a row, a tree of branches on the row's arm
        # index goes to the arm's body. The chain does not run: its reads
        # and its `===` sends have no effect and give the same result.
        #
        # All other cases run the chain as `case_when` does. In it, the
        # site gives each value that it read from its constant's cell to
        # the kernel for a check, one time for each state
        # (`zr_case_prove`). The arm that the chain selects goes into the
        # table if the kernel proved each value that the chain tested
        # (`zr_case_fill`). The stamps are read before the chain, so a
        # change that the chain causes (an autoload, a definition in a
        # `===`) makes the kernel add no row.
        def class_case(node)
          base = @sp
          subject_at = value_offset(reserve(1))
          subject = expr(node.subject)
          @f.store(subject, @rec, subject_at)
          cc = site_cache(node, "case", "CaseCache")
          cell = @l.layout("CaseCache")
          ms = @f.fetch("i64", static("site_stamp"))
          cs = @f.fetch("i64", static("const_stamp"))
          klass = class_of(subject)
          bodies = node.clauses.map { @f.label }
          other = @f.label
          probe = @f.label
          found = @f.label
          chain = @f.label
          merge, (result,) = @f.block(["i64"])
          valid = @f.band(@f.band(@f.icmp("eq", @f.fetch("i64", cc, off(cell, "mstamp")), ms),
                                  @f.icmp("eq", @f.fetch("i64", cc, off(cell, "cstamp")), cs)),
                          @f.icmp("eq", @f.fetch("i64", cc, off(cell, "cref")), @cref))
          @f.brif(valid, probe, chain)
          switch(probe)
          row = case_row(@f.fetch("i64", cc, off(cell, "table")), klass)
          @f.brif(@f.icmp("eq", @f.fetch("i64", row, off(@l.layout("CaseRow"), "klass")), klass), found, chain)
          switch(found)
          arm_jump(@f.fetch("i64", row, off(@l.layout("CaseRow"), "arm")), bodies + [other], 0)
          switch(chain)
          tested = 0
          node.clauses.each_with_index do |(values, _), arm|
            values.each do |value|
              tested += 1
              chosen = @f.label
              miss = @f.label
              j = tested - 1
              read = ->(n) { n.equal?(value) ? proved_read(value, j, cc, ms, cs) : expr(n) }
              cond = staged([value, Hir::Slot.new(base, value.line)], evaluate: read) do |slots|
                at_node(value)
                match = Hir::Send.of(value, :===, [node.subject], value.line)
                truthy(checked(cached_send(match, @f.fetch("i64", slots), imm(1), @f.iadd(slots, imm(8)), @qnil, mode: 0)))
              end
              @f.brif(cond, chosen, miss)
              switch(chosen)
              kernel("zr_case_fill", cc, @cref, klass, imm(arm), imm(tested), ms, cs)
              @f.jump(bodies[arm])
              switch(miss)
            end
          end
          kernel("zr_case_fill", cc, @cref, klass, imm(node.clauses.size), imm(tested), ms, cs)
          @f.jump(other)
          node.clauses.each_with_index do |(_, body), arm|
            switch(bodies[arm])
            v = expr(body)
            @f.jump(merge, [v]) unless @f.terminated?
          end
          switch(other)
          v = node.else_body ? expr(node.else_body) : @qnil
          @f.jump(merge, [v]) unless @f.terminated?
          switch(merge)
          @sp = base
          result
        end

        # Reads the `when` value at index `j` of a `class_case`. If the
        # read came from its constant's cell and `j` is the value that the
        # cache entry is due to check, the kernel checks it.
        def proved_read(value, j, cc, ms, cs)
          v, hit = const_hit_read(value)
          prove = @f.label
          onward = @f.label
          due = @f.icmp("eq", @f.fetch("i64", cc, off(@l.layout("CaseCache"), "due")), imm(j))
          @f.brif(@f.band(due, @f.icmp("ne", hit, imm(0))), prove, onward)
          switch(prove)
          kernel("zr_case_prove", cc, @cref, v, imm(j), ms, cs)
          @f.jump(onward)
          switch(onward)
          v
        end

        # The row of `table` for class `klass`, by the hash of
        # `zr_case_fill`: the address over CELL_MIN (32), mixed with the
        # address over CELL_MIN * CASE_ROWS, modulo CASE_ROWS (32).
        def case_row(table, klass)
          h = @f.band(@f.bxor(@f.ushr(klass, imm(5)), @f.ushr(klass, imm(10))), imm(@l.const("CASE_ROWS") - 1))
          @f.iadd(table, @f.ishl(h, imm(Math.log2(@l.layout("CaseRow").size).to_i)))
        end

        # Jumps to `targets[arm - first]` by a balanced tree of branches on
        # the arm index. The IR has no jump table, so this costs about
        # log2 of the arm count in branches.
        def arm_jump(arm, targets, first)
          return @f.jump(targets[0]) if targets.size == 1

          half = targets.size / 2
          low = @f.label
          high = @f.label
          @f.brif(@f.icmp("slt", arm, imm(first + half)), low, high)
          switch(low)
          arm_jump(arm, targets[0...half], first)
          switch(high)
          arm_jump(arm, targets[half..], first + half)
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

        # Calls the block at the site, as zr_yield does: test that there
        # is a block, then call its function through the Proc. The
        # kernel's yield first polls for preemption. A program's function
        # polls at its entry and at each back edge, but the core's
        # functions never poll (`preempt`). So a core iterator's `yield`
        # uses the kernel's yield, or `loop { }` would never yield to the
        # scheduler. With no block, the kernel's yield also runs, and it
        # raises.
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

        # `return`: leaves the method, or, from a block, unwinds through
        # the runtime to the method that made the block.
        def return_from(node)
          v = expr(node.value)
          # A `return` in an eval or in `class << self` returns from the
          # method that holds the scope.
          if @kind == :eval || @kind == :sclass
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

        # zr_require's kinds. `hidden` is eval support's own load, which the
        # program does not see. `declared` is an autoload only: the
        # feature is already loaded, so the name is declared and no entry
        # waits for a file.
        REQUIRE_KINDS = { require: 0, require_relative: 1, load: 2, hidden: 3, computed: 4, declared: 5 }.freeze

        # A require of a file in the program runs that file's toplevel,
        # once unless it is a load. A relative name with no file raises
        # LoadError.
        def require_unit(node)
          at_node(node)
          shown = Paths.shown(node.path)
          path = @f.symbol_value(@f.symbol(@l.literal(shown)))
          return checked(kernel("zr_load_error", path, imm(shown.bytesize))) unless node.unit

          fn = @f.func_addr(@f.callee(@l.unit_entry(node.unit), [], "i64"))
          checked(kernel("zr_require", kernel("zr_str_new", path, imm(shown.bytesize)), fn, imm(REQUIRE_KINDS.fetch(node.kind))))
        end

        # `autoload :Name, "feature"`: the constant's entry waits for the
        # unit, and the first read runs it. The receiver and the feature
        # stay in record slots while the path is made, because its
        # allocation can start a collection.
        def autoload_unit(node)
          at_node(node)
          base = reserve(2)
          @f.store(node.recv ? expr(node.recv) : @self, @rec, value_offset(base))
          @f.store(kernel("zr_str_new", @f.symbol_value(@f.symbol(@l.literal(node.feature))), imm(node.feature.bytesize)), @rec, value_offset(base + 1))
          shown = Paths.shown(node.path)
          path = kernel("zr_str_new", @f.symbol_value(@f.symbol(@l.literal(shown))), imm(shown.bytesize))
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
            @l.unsupported(node, "redo outside a block or loop") unless @kind == :block
            through_ensures(@qnil)
            preempt
            @f.jump(@body_label)
          end
          switch(@f.label, open: true)
          @qnil
        end

        # `break`/`next`: leave the innermost loop if one encloses the
        # statement, else leave the block.
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
          @l.unsupported(node, "#{kind} outside a block or loop") unless @kind == :block
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
