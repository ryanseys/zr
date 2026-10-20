# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # Branches, loops, short-circuit operators, and the jumps that leave
      # a block or a loop.
      module Control
        # @type instance: Function
        # @rbs @blk: String
        # @rbs @body_label: String?
        # @rbs @cref: String
        # @rbs @f: IR::Function
        # @rbs @kind: Function::kind
        # @rbs @l: Lower
        # @rbs @loops: Array[Loop]
        # @rbs @proc: String
        # @rbs @proc_layout: Machine::Layout
        # @rbs @qnil: String
        # @rbs @rec: String
        # @rbs @regions: Array[Regions::Region]
        # @rbs @self: String
        # @rbs @sp: Integer

        private

        # The condition a Value's truthiness gives: anything but nil and
        # false. false is 0, so a Value is falsy when only nil's bits are
        # set (CRuby's RTEST).
        #: (String v) -> String
        def truthy(v)
          @f.icmp("ne", @f.band(v, imm(~@l.const("QNIL"))), imm(0))
        end

        # Lowers the test `node` as a branch: to `yes` if it is truthy,
        # else to `no`. An `&&` or `||` branches on its left side, and
        # evaluates its right side only if the left side does not decide.
        # Its value is never made, so a test with several parts is a chain
        # of branches with no join. A comparison of plain reads branches
        # on the comparison (`Sends#relation_jump`). All other nodes are
        # tested as values.
        #: (Hir::node node, String yes, String no) -> void
        def jump_if(node, yes, no)
          case node
          when Hir::And, Hir::Or
            rest = @f.label
            node.is_a?(Hir::And) ? jump_if(node.left, rest, no) : jump_if(node.left, yes, rest)
            switch(rest)
            jump_if(node.right, yes, no)
          else
            return relation_jump(node, yes, no) if node.is_a?(Hir::Send) && relation_test?(node)

            v = expr(node)
            @f.brif(truthy(v), yes, no) unless @f.terminated?
          end
        end

        #: (Hir::If node) -> String
        def branch(node)
          then_b = @f.label
          else_b = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
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
        #: (Hir::While node) -> String
        def loop_while(node)
          head = @f.label
          body = @f.label
          out = @f.label
          done, (result,) = @f.block(["i64"]) #: [String, [String]]
          @loops << Loop.new(head: head, body: body, done: done, depth: @regions.size)
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

        # A safe point (lib/zr/runtime/kernel/send.rb): read the poll word, and
        # call the kernel only if it is set. Under wasm, the count is the
        # clock, and this subtracts one tick.
        #
        # Not in the runtime's own Ruby. The scheduler and the waits are
        # written there, and a yield from inside them would be a switch
        # during a switch. The runtime's long loops are the iterators, and
        # the kernel counts ticks at their yields.
        #: () -> void
        def preempt
          return if @l.internal?

          expired = @f.cold(@f.label)
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
        #: (Hir::And | Hir::Or node) -> String
        def logical(node)
          left = expr(node.left)
          rest = @f.label
          skip = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
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
        #: (Hir::Case node) -> String
        def case_when(node)
          return class_case(node) if class_case?(node)
          return symbol_case(node) if symbol_case?(node)

          base = @sp
          subject_at = value_offset(reserve(1))
          @f.store(expr(node.subject), @rec, subject_at) if node.subject
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          node.clauses.each do |values, body|
            hit = @f.label
            values.each do |value|
              miss = @f.label
              cond = if value.is_a?(Hir::Splat) && node.subject
                       at_node(value)
                       truthy(checked(kernel("zr_case_any", @f.fetch("i64", @rec, subject_at), expr(value.value), imm(eqq_mode(value.value)))))
                     elsif value.is_a?(Hir::Splat)
                       at_node(value)
                       truthy(checked(kernel("zr_any_truthy", expr(value.value))))
                     elsif node.subject
                       when_eqq(node, value, base)
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

        # Sends `value === subject` through the site's own cell, with no
        # visibility check, and gives the truth of the result. The subject
        # is in the record slot at `base`.
        #: (Hir::Case node, Hir::node value, Integer base) -> String
        def when_eqq(node, value, base)
          subject = node.subject or raise ArgumentError, "a case with no subject has no `===`"
          staged([value, Hir::Slot.new(base, value.line)]) do |slots|
            at_node(value)
            match = Hir::Send.of(value, :===, [subject], value.line, using: node.using)
            activate(match)
            mode = eqq_mode(value) | (match.using ? Sends::SEND_USING : 0)
            truthy(checked(cached_send(match, @f.fetch("i64", slots), imm(1), @f.iadd(slots, imm(8)), @qnil, mode: mode)).tap { deactivate(match) })
          end
        end

        # The core's own `when nil` or `when Float` is a type test in ruby's
        # C, which no program's `===` answers: its send finds the core's
        # own method, also for a String, Regexp or Range literal. A value
        # that the core was given is sent as any. In
        # eval's compiler every `when` is the core's, as ruby's compiler is C.
        #: (Hir::node value) -> Integer
        def eqq_mode(value)
          return Sends::SEND_CORE if @l.support?

          fixed = [Hir::Literal, Hir::FrozenString, Hir::RegexpLit, Hir::RangeLit, Hir::ConstRead, Hir::Core].any? { |kind| value.is_a?(kind) }
          fixed && @l.internal? ? Sends::SEND_CORE : 0
        end

        # Whether a `case` compares its subject with symbols only
        # (`symbol_case`): it has a subject, and each `when` value is a
        # symbol literal (not a splat, and not a symbol with
        # interpolation).
        #: (Hir::Case node) -> bool
        def symbol_case?(node)
          return false if node.subject.nil?

          node.clauses.all? { |values, _| values.all? { |v| v.is_a?(Hir::Literal) && v.value.is_a?(Symbol) } }
        end

        # A `case` on symbol arms. While Symbol#=== is the runtime's own
        # (GATE_SYM_EQQ), `:sym === subject` is identity, as symbol.c's
        # sym_equal is. Thus the site compares the subject word with each
        # symbol word in the order of the arms, and the first equal one
        # selects its arm. A symbol is an immediate, so each test is one
        # compare and one branch, with no send. An id that the link
        # numbers comes from the unit's pool, which the function reads one
        # time. A subject that is not a symbol (a String with the same
        # name, for example) is equal to no symbol word, as `===` is false
        # for it. CRuby's opt_case_dispatch does the same while `===` on
        # Symbol is not redefined.
        #
        # When the gate is closed (a def of `===` on Symbol, a prepend, a
        # `refine Symbol`), the site sends `===` for each value, as
        # `case_when` does.
        #: (Hir::Case node) -> String
        def symbol_case(node)
          base = @sp
          subject_at = value_offset(reserve(1))
          subject = expr(node.subject)
          @f.store(subject, @rec, subject_at)
          fast = @f.label
          chain = @f.label
          bodies = node.clauses.map { @f.label }
          other = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(gate_clear("GATE_SYM_EQQ"), fast, chain)
          switch(fast)
          node.clauses.each_with_index do |(values, _), arm|
            values.each do |value|
              miss = @f.label
              name = value.value if value.is_a?(Hir::Literal)
              raise ArgumentError, "a symbol case has only symbol values" unless name.is_a?(Symbol)

              @f.brif(@f.icmp("eq", subject, symbol(name)), bodies[arm], miss)
              switch(miss)
            end
          end
          @f.jump(other)
          switch(chain)
          node.clauses.each_with_index do |(values, _), arm|
            values.each do |value|
              miss = @f.label
              @f.brif(when_eqq(node, value, base), bodies[arm], miss)
              switch(miss)
            end
          end
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

        # The fewest `when` values for which a `case` gets a table. With
        # fewer, the chain's inline class tests cost less than the probe.
        CLASS_CASE_MIN = 6

        # Whether a `case` gets a table from the subject's class to its
        # arm (`class_case`): it has a subject, each `when` value is a
        # constant path (`A`, `::A`, `A::B`, with no other expression in
        # it), and it has at least CLASS_CASE_MIN of them. A traced
        # program keeps the chain, so each `===` gives its events.
        #: (Hir::Case node) -> bool
        def class_case?(node)
          return false if node.subject.nil? || traced?

          values = node.clauses.flat_map(&:first)
          values.size >= CLASS_CASE_MIN && values.all? { |v| constant_path?(v) }
        end

        #: (Hir::scope node) -> bool
        def constant_path?(node)
          node.is_a?(Hir::ConstRead) && (node.scope.nil? || node.scope == :top || constant_path?(node.scope))
        end

        # A `case` on class arms, in constant time for a subject class that
        # the site saw before. The site's cache entry (CaseCache,
        # lib/zr/runtime/kernel/cache.rb) has a table from a class to an arm. If
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
        #: (Hir::Case node) -> String
        def class_case(node)
          base = @sp
          subject_at = value_offset(reserve(1))
          tested_node = node.subject or raise ArgumentError, "a class case has a subject"
          subject = expr(tested_node)
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
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
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
              raise ArgumentError, "a class case has only constant values" unless value.is_a?(Hir::ConstRead)

              tested += 1
              chosen = @f.label
              miss = @f.label
              j = tested - 1
              read = ->(n) { n.equal?(value) ? proved_read(value, j, cc, ms, cs) : expr(n) }
              cond = staged([value, Hir::Slot.new(base, value.line)], evaluate: read) do |slots|
                at_node(value)
                match = Hir::Send.of(value, :===, [tested_node], value.line)
                truthy(checked(cached_send(match, @f.fetch("i64", slots), imm(1), @f.iadd(slots, imm(8)), @qnil, mode: eqq_mode(value))))
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
        #: (Hir::ConstRead value, Integer j, String cc, String ms, String cs) -> String
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
        #: (String table, String klass) -> String
        def case_row(table, klass)
          h = @f.band(@f.bxor(@f.ushr(klass, imm(5)), @f.ushr(klass, imm(10))), imm(@l.const("CASE_ROWS") - 1))
          @f.iadd(table, @f.ishl(h, imm(Math.log2(@l.layout("CaseRow").size).to_i)))
        end

        # Jumps to `targets[arm - first]` by a balanced tree of branches on
        # the arm index. The IR has no jump table, so this costs about
        # log2 of the arm count in branches.
        #: (String arm, Array[String] targets, Integer first) -> void
        def arm_jump(arm, targets, first)
          return @f.jump(targets[0]) if targets.size == 1

          half = targets.size / 2
          low = @f.label
          high = @f.label
          @f.brif(@f.icmp("slt", arm, imm(first + half)), low, high)
          switch(low)
          arm_jump(arm, targets.first(half), first)
          switch(high)
          arm_jump(arm, targets.drop(half), first + half)
        end

        #: (Hir::Yield node) -> String
        def yield_block(node)
          # The keywords go as a call's do (`Sends#keyword_args`): `k: v`
          # pairs by a table, a lone `**h` lent, any other as one Hash.
          parts = node.args + keyword_args(node)
          if parts.any?(Hir::Splat)
            # The arguments go on the spread stack, as a call's do.
            slot = reserve(2)
            @f.store(kernel("zr_spread_mark"), @rec, value_offset(slot + 1))
            ary = gather(parts, slot, spread: true)
            at_node(node)
            argc = yield_keyword_argc(node, array_len(ary), array_ptr(ary))
            r = checked(block_call(argc, array_ptr(ary)))
            kernel("zr_spread_give", @f.fetch("i64", @rec, value_offset(slot + 1))) unless @f.terminated?
            @sp = slot
            return r
          end

          staged(parts) do |argv|
            at_node(node)
            checked(block_call(yield_keyword_argc(node, imm(parts.size), argv), argv))
          end
        end

        # A yield's count, as `Sends#keyword_argc` makes a call's: an empty
        # Hash still counts as keywords given (zr_kw_argc_yield), and so
        # does a splat's flagged Hash (zr_kw_ruby2_out_yield).
        #: (Hir::Yield node, String argc, String argv) -> String
        def yield_keyword_argc(node, argc, argv)
          kwargs = node.kwargs
          return node.args.any?(Hir::Splat) ? kernel("zr_kw_ruby2_out_yield", argc, argv) : argc unless kwargs
          return kernel("zr_kw_argc_lent_yield", argc, argv) if lent_keywords?(node)
          return kernel("zr_kw_argc_yield", argc, argv) unless Scope.literal_keywords?(kwargs)

          keys = kwargs.pairs.each_slice(2).map do |key, _|
            literal = key #: Hir::Literal
            literal.value #: Symbol
          end
          @f.store(@f.symbol_value(@f.symbol(@l.keyword_table([keys.size, *keys]))), @task_addr, off(@task, "kw"), region: :task)
          argc
        end

        # Calls the block at the site, as zr_yield does: test that there
        # is a block, then call its function through the Proc. The
        # kernel's yield first polls for preemption. A program's function
        # polls at its entry and at each back edge, but the core's
        # functions never poll (`preempt`). So a core iterator's `yield`
        # uses the kernel's yield, or `loop { }` would never yield to the
        # scheduler. With no block, the kernel's yield also runs, and it
        # raises.
        #: (String argc, String argv) -> String
        def block_call(argc, argv)
          return kernel("zr_yield", @blk, argc, argv) if @l.internal?

          none = @f.label
          some = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
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
        #: (Hir::Return node) -> String
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
          elsif @kind == :class || @kind == :module
            # Only an inlined block's `return` is in a body.
            at_node(node)
            leave(through_ensures(checked(kernel("zr_body_return", @rec, v)), line: node.line), line: node.line)
          else
            leave(through_ensures(v, line: node.line), line: node.line)
          end
          @qnil
        end

        # zr_require's kinds. `hidden` is eval support's own load, which the
        # program does not see. `declared` is an autoload only: the
        # feature is already loaded, so the name is declared and no entry
        # waits for a file.
        REQUIRE_KINDS = { require: 0, require_relative: 1, load: 2, hidden: 3, computed: 4, declared: 5 }.freeze #: Hash[Symbol, Integer]

        # A require of a file in the program runs that file's toplevel,
        # once unless it is a load. A relative name with no file raises
        # LoadError.
        #: (Hir::Require node) -> String
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
        #: (Hir::Autoload node) -> String
        def autoload_unit(node)
          at_node(node)
          base = reserve(2)
          @f.store(node.recv ? expr(node.recv) : @self, @rec, value_offset(base))
          # A feature that names a file (`"#{__dir__}/x"`) is written as the
          # build writes paths, as `__dir__` gives it at run time.
          written = Paths.shown(node.feature)
          name = kernel("zr_str_new", @f.symbol_value(@f.symbol(@l.literal(written))), imm(written.bytesize))
          @f.store(name, @rec, value_offset(base + 1))
          shown = Paths.shown(node.path)
          path = kernel("zr_str_new", @f.symbol_value(@f.symbol(@l.literal(shown))), imm(shown.bytesize))
          recv = @f.fetch("i64", @rec, value_offset(base))
          feature = @f.fetch("i64", @rec, value_offset(base + 1))
          fn = node.unit ? @f.func_addr(@f.callee(@l.unit_entry(node.unit), [], "i64")) : imm(0)
          key = if node.declared then :declared
                elsif node.unit then :require
                else :computed
                end
          kind = REQUIRE_KINDS.fetch(key)
          result = checked(kernel("zr_autoload", recv, sym_word(node.name), feature, fn, @cref, imm(kind), path))
          release(base)
          result
        end

        # `redo`: the innermost loop's body again without its test, or the
        # block's body again with the parameters as they are.
        #: (Hir::Redo node) -> String
        def redo_body(node)
          if (loop = @loops.last)
            through_ensures(@qnil, loop.depth)
            preempt
            @f.jump(loop.body)
          else
            # Only a block's scope has a body label.
            label = @body_label || @l.unsupported(node, "redo outside a block or loop")
            through_ensures(@qnil)
            preempt
            @f.jump(label)
          end
          switch(@f.label, open: true)
          @qnil
        end

        # A block's `redo` starts again here (`Hir::RedoPoint`): in the
        # block's own function, or in the loop that a call inlines it into.
        #: () -> String
        def redo_point
          label = @f.label
          @f.jump(label)
          switch(label)
          if (loop = @loops.last)
            @loops[-1] = loop.with(body: label)
          else
            @body_label = label
          end
          @qnil
        end

        # `break`/`next`: leave the innermost loop if one encloses the
        # statement, else leave the block.
        #: (Hir::Break | Hir::Next node, Symbol kind) -> String
        def jump_out(node, kind)
          v = expr(node.value)
          if (loop = @loops.last)
            v = through_ensures(v, loop.depth, line: node.line)
            if kind == :break
              @f.jump(loop.done, [v])
            elsif loop.step
              @f.jump(loop.step, [v])
            else
              # A back edge like the one at the body's end.
              preempt
              @f.jump(loop.head)
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
