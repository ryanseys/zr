# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # A small def of the unit, inlined at a site that calls it.
      #
      # The site keeps its cell and its class-and-stamp test. On a hit
      # whose direct entry is the def's own body, the body runs here with
      # no frame. Every guard that fails (a cell miss, a different
      # receiver kind, an operator result outside the fixnums, a closed
      # gate) jumps to `bail`: the normal call, which runs the def from
      # its start. So the copy can contain only code with no side
      # effects: reads of parameters, of self's ivars through their
      # guessed entries, of readers and type checks through the def's
      # own site cells, fixnum arithmetic, branches and a return. No
      # call, no store, no allocation. The copy shares the def's cells
      # (`site_cell`), so a bail that runs the def fills the cells for
      # the copy's next run.
      #
      # A def whose body is not fully pure can still start with a
      # decision that the copy can make: a pure test with a pure branch
      # (fib's `n < 2 ? n : ...`, ack's `m == 0`), or a guard clause
      # (`return x if test`). The copy returns that branch at the site.
      # All other paths bail to the def's own call, which does the test
      # again. So the leaves of a recursion (half its calls) make no call.
      #
      # Visible effects: the inlined def has no frame, so it raises no
      # SystemStackError and polls one time less at entry. No backtrace
      # is taken inside the copy, because nothing in it raises.
      module Inline
        # The maximum HIR node count of a candidate's body.
        LIMIT = 24
        # The one-argument sends that a copy handles: an Integer operator
        # on fixnums, identity for BasicObject's `==`/`!=`, a type check,
        # and a `case` branch on a class.
        ARGUED = %i[is_a? kind_of? ===].freeze
        # The pattern of a reader method's name.
        READER = /\A[a-z_][A-Za-z0-9_]*\z/

        # A copy that runs at a site: the value of each parameter by name,
        # the block that its `return` goes to (`done`; not `exit`, which is
        # Kernel's), and the block that each failed guard goes to.
        Site = Data.define(:locals, :done, :bail)

        # The defs in the unit tree `body` that a site can inline, by name.
        # Each is the only def of its name in the unit, has only required
        # positionals (four at most, the direct entry's shape) and no other
        # local, and has a body that passes `pure?` or `leads?`. A def with
        # a receiver (`def self.x`) is never a candidate, and it also
        # disqualifies its name.
        def self.candidates(body)
          defs = Hash.new { |h, k| h[k] = [] }
          each_def(body) { |d| defs[d.name] << d }
          defs.each_with_object({}) do |(name, list), out|
            d = list.first
            next unless list.size == 1 && d.receiver.nil? && d.params.plain? && d.params.required.size <= DIRECT_ARGS
            next unless d.params.required.all?(Symbol) && d.locals == d.params.required && d.params.block.nil?

            given = d.params.required.size + 1
            out[name] = d if pure?(d.body, [given]) || leads?(d.body, [given])
          end
        end

        # Whether `body` starts with a decision that the copy can make: an
        # `if` with a pure test and a pure branch. It is the whole body, or
        # a guard clause (one branch is a `return`) before the rest.
        def self.leads?(body, count)
          body = body.stmts.first while body.is_a?(Hir::Seq) && body.stmts.size == 1
          test = body.is_a?(Hir::Seq) ? body.stmts.first : body
          return false unless test.is_a?(Hir::If) && pure?(test.cond, count)

          arms = [test.yes, test.no].compact
          arms = arms.select { |arm| returns?(arm) } unless test.equal?(body)
          arms.any? { |arm| pure?(arm, count.dup) }
        end

        # Whether `node` ends in a `return`.
        def self.returns?(node)
          node = node.stmts.last if node.is_a?(Hir::Seq)
          node.is_a?(Hir::Return)
        end

        # Every Def under `node`, at any depth. The walk goes into class
        # bodies, blocks and defs.
        def self.each_def(node, &)
          case node
          when Hir::Def
            yield node
            each_def(node.body, &)
          when Hir::Seq then node.stmts.each { |n| each_def(n, &) }
          when Hir::ClassDef, Hir::ModuleDef, Hir::SingletonClassDef then each_def(node.body, &)
          when Hir::If
            each_def(node.cond, &)
            each_def(node.yes, &) if node.yes
            each_def(node.no, &) if node.no
          when Hir::While
            each_def(node.cond, &)
            each_def(node.body, &)
          when Hir::Send
            each_def(node.recv, &) if node.recv
            node.args.each { |a| each_def(a, &) }
            each_def(node.block.body, &) if node.block.is_a?(Hir::Block)
          when Hir::Begin
            each_def(node.body, &) if node.body
          end
        end

        # Whether a copy can lower `node`. Adds its node count to `count`
        # (a one-element Array with the running total).
        def self.pure?(node, count)
          return false if (count[0] += 1) > LIMIT

          case node
          when Hir::Seq then node.stmts.all? { |n| pure?(n, count) }
          when Hir::If then pure?(node.cond, count) && (node.yes.nil? || pure?(node.yes, count)) && (node.no.nil? || pure?(node.no, count))
          when Hir::And, Hir::Or then pure?(node.left, count) && pure?(node.right, count)
          when Hir::Not then pure?(node.value, count)
          when Hir::Return then node.value.nil? || pure?(node.value, count)
          when Hir::Literal then immediate_literal?(node.value)
          when Hir::SelfRef, Hir::IvarRead then true
          when Hir::Local then node.depth.zero?
          when Hir::Send then pure_send?(node, count)
          else false
          end
        end

        def self.immediate_literal?(v)
          case v
          when Integer then v.bit_length < 63
          when Float then flonum?(v)
          when Symbol, nil, true, false then true
          else false
          end
        end

        # Whether the double `v` is a flonum (`Expressions#flonum_word`).
        def self.flonum?(v)
          b = [v].pack("E").unpack1("Q<")
          top = (b >> 60) & 7
          b.zero? || (b != 0x3000000000000000 && (top == 3 || top == 4))
        end

        # A send with an explicit receiver and no block, keywords, splat or
        # refinement: a reader or `nil?` with no argument, or one of the
        # ARGUED forms.
        def self.pure_send?(node, count)
          return false if node.recv.nil? || node.vcall || node.block || node.kwargs || node.safe || node.interp || node.using || node.write
          return false unless pure?(node.recv, count) && node.args.all? { |a| !a.is_a?(Hir::Splat) && pure?(a, count) }

          case node.args.size
          when 0 then node.name == :nil? || node.name.match?(READER)
          when 1 then Sends::OPS.key?(node.name) || ARGUED.include?(node.name)
          else false
          end
        end

        private

        # The def that the call `node` can inline, if the site permits it:
        # the def's argument count, no block, no keywords, no splat, no
        # `using`, not traced (a trace sees every frame), and not in the
        # core (its sends have their own modes).
        def inline_candidate(node)
          return nil if traced? || @l.internal? || node.block || node.kwargs || node.using || node.args.any?(Hir::Splat)

          d = @l.inline_def(node.name)
          d if d && d.params.required.size == node.args.size
        end

        # The copy of `d`'s body at the site, with `recv` as its self and
        # `given` as its parameters. Every guard that fails jumps to
        # `bail`. Returns the body's value.
        def inline_body(d, recv, given, bail)
          exit, (result,) = @f.block(["i64"])
          saved = [@self, @inline]
          @self = recv
          @inline = Site.new(d.params.required.zip(given).to_h, exit, bail)
          v = spec_leading(d.body)
          @f.jump(exit, [v]) unless @f.terminated?
          @self, @inline = saved
          switch(exit)
          result
        end

        # The copy of a candidate's body: a pure body in full, or the
        # leading test (`leads?`). Its branches and later statements are
        # copied if pure, else they bail.
        def spec_leading(body)
          return spec(body) if Inline.pure?(body, [0])

          body = body.stmts.first while body.is_a?(Hir::Seq) && body.stmts.size == 1
          body.is_a?(Hir::If) ? spec_branch(body) : spec_seq(body)
        end

        # The value of `node` in the copy: `expr` for the nodes that pass
        # `pure?`, with each miss a jump to the bail block. Code that the
        # copy cannot run (a branch of a leading test that calls, or the
        # rest after a guard clause) is only a bail.
        def spec(node)
          unless Inline.pure?(node, [0])
            @f.jump(@inline.bail)
            return @qnil
          end

          case node
          when Hir::Seq then spec_seq(node)
          when Hir::If then spec_branch(node)
          when Hir::And, Hir::Or then spec_logical(node)
          when Hir::Not then spec_negate(node)
          when Hir::Return then spec_return(node)
          when Hir::Literal then literal(node)
          when Hir::SelfRef then @self
          when Hir::Local then @inline.locals.fetch(node.name)
          when Hir::IvarRead then spec_ivar_read(node)
          when Hir::Send then spec_send(node)
          else @l.refuse(node, "#{node.class.name.split("::").last} is not inlined")
          end
        end

        def spec_seq(node)
          v = @qnil
          node.stmts.each do |n|
            v = spec(n)
            break if @f.terminated?
          end
          v
        end

        # A comparison of two fixnums branches on the comparison, as
        # `Sends#relation_jump` does. `==` and `!=` of other values are
        # identity tests (if the def's cell permits), tested as a value.
        def spec_jump_if(node, yes, no)
          case node
          when Hir::And, Hir::Or
            rest = @f.label
            node.is_a?(Hir::And) ? spec_jump_if(node.left, rest, no) : spec_jump_if(node.left, yes, rest)
            switch(rest)
            spec_jump_if(node.right, yes, no)
          else
            return spec_relation_jump(node, yes, no) if spec_relation?(node)

            v = spec(node)
            @f.brif(truthy(v), yes, no) unless @f.terminated?
          end
        end

        def spec_relation?(node)
          node.is_a?(Hir::Send) && Sends::RELATIONS.key?(node.name) && node.args.size == 1 && Inline.pure?(node, [0])
        end

        def spec_relation_jump(node, yes, no)
          recv = spec(node.recv)
          arg = spec(node.args[0])
          fixnums = @f.label
          rest = @f.label
          @f.brif(@f.band(fixnums?(recv, arg), gate_clear(Sends::OPS.fetch(node.name))), fixnums, rest)
          switch(fixnums)
          @f.brif(@f.icmp(Sends::RELATIONS.fetch(node.name), recv, arg), yes, no)
          switch(rest)
          return @f.jump(@inline.bail) unless %i[== !=].include?(node.name)

          merge, (v,) = @f.block(["i64"])
          spec_identity(node, recv, arg, merge)
          switch(merge)
          @f.brif(truthy(v), yes, no)
        end

        def spec_branch(node)
          then_b = @f.label
          else_b = @f.label
          merge, (result,) = @f.block(["i64"])
          spec_jump_if(node.cond, then_b, else_b)
          switch(then_b)
          v = node.yes ? spec(node.yes) : @qnil
          @f.jump(merge, [v]) unless @f.terminated?
          switch(else_b, open: !@f.terminated?)
          v = node.no ? spec(node.no) : @qnil
          @f.jump(merge, [v]) unless @f.terminated?
          switch(merge)
          result
        end

        def spec_logical(node)
          left = spec(node.left)
          rest = @f.label
          skip = @f.label
          merge, (result,) = @f.block(["i64"])
          cond = truthy(left)
          node.is_a?(Hir::And) ? @f.brif(cond, rest, skip) : @f.brif(cond, skip, rest)
          switch(skip)
          @f.jump(merge, [left])
          switch(rest)
          right = spec(node.right)
          @f.jump(merge, [right]) unless @f.terminated?
          switch(merge)
          result
        end

        # `!v` for nil, true and false under GATE_NOT (`Sends#negate`).
        # All other receivers bail.
        def spec_negate(node)
          v = spec(node.value)
          go = @f.label
          boolean = @f.icmp("eq", @f.bor(v, imm(28)), imm(28))
          @f.brif(@f.band(boolean, gate_clear("GATE_NOT")), go, @inline.bail)
          switch(go)
          @f.csel(truthy(v), imm(@l.const("QFALSE")), imm(@l.const("QTRUE")))
        end

        def spec_return(node)
          v = node.value ? spec(node.value) : @qnil
          @f.jump(@inline.done, [v]) unless @f.terminated?
          @qnil
        end

        # `@name` of the copy's self, through the def's own guessed entry.
        def spec_ivar_read(node)
          ivar = ivar_name(node.name)
          ic = site_cache(node, "iv", "IvarCache")
          row = guessed_ivar_row(ic, ivar, @inline.bail, writing: false)
          found = @f.fetch("i64", row, off(@l.layout("IvEntry"), "value"))
          @f.csel(@f.icmp("eq", found, qundef), @qnil, found)
        end

        def spec_send(node)
          recv = spec(node.recv)
          args = node.args.map { |a| spec(a) }
          merge, (result,) = @f.block(["i64"])
          case node.args.size
          when 0 then node.name == :nil? ? spec_nil_p(recv, merge) : spec_reader(node, recv, merge)
          when 1 then spec_argued(node, recv, args[0], merge)
          end
          switch(merge)
          result
        end

        # `recv.nil?` under GATE_NIL_P: nil, or a ranked class (a class
        # under Object, where Kernel's `nil?` applies).
        def spec_nil_p(recv, merge)
          is_nil = @f.label
          not_nil = @f.label
          ranked = @f.label
          @f.brif(gate_clear("GATE_NIL_P"), is_nil, @inline.bail)
          switch(is_nil)
          @f.brif(@f.icmp("eq", recv, @qnil), not_nil, ranked)
          switch(not_nil)
          @f.jump(merge, [imm(@l.const("QTRUE"))])
          switch(ranked)
          answer = @f.label
          @f.brif(ranked?(class_of(recv)), answer, @inline.bail)
          switch(answer)
          @f.jump(merge, [imm(@l.const("QFALSE"))])
        end

        # A reader through the def's own cell. If the receiver is a cell
        # whose class the cell has at the site stamp, with the shape of a
        # reader or of a struct member's reader, read the ivar or the member
        # inline. All other cases bail.
        def spec_reader(node, recv, merge)
          cc = site_cache(node, "ic", "CallCache", Sends::CALL_WAYS)
          cell = @l.layout("CallCache")
          heap = @f.label
          hit = @f.label
          shaped = @f.label
          @f.brif(cellp(recv), heap, @inline.bail)
          switch(heap)
          klass = @f.fetch("i64", recv, off(@l.layout("RBasic"), "klass"))
          @f.brif(cell_hit(cc, klass), hit, @inline.bail)
          switch(hit)
          held = @f.fetch("i64", cc, off(cell, "shape"))
          @f.brif(@f.bor(@f.icmp("eq", held, imm(@l.const("SHAPE_READER"))), struct_member?(:reader, held)), shaped, @inline.bail)
          switch(shaped)
          accessor_in_place(:reader, recv, @f.fetch("i64", cc, off(cell, "entry")), nil, merge, @inline.bail, held)
        end

        # An operator on two fixnums under its gate. `==` and `!=` by
        # identity if the def's own cell has BasicObject's methods. A type
        # check by the classes. All other cases bail.
        def spec_argued(node, recv, arg, merge)
          op = node.name
          if Sends::OPS.key?(op)
            fixnums = @f.label
            rest = @f.label
            both = @f.icmp("ne", @f.band(@f.band(recv, arg), imm(1)), imm(0))
            @f.brif(@f.band(both, gate_clear(Sends::OPS.fetch(op))), fixnums, rest)
            switch(fixnums)
            @f.jump(merge, [fast_path(op, recv, arg, @inline.bail)])
            switch(rest)
            return spec_identity(node, recv, arg, merge) if %i[== !=].include?(op)

            @f.jump(@inline.bail)
          elsif op == :===
            spec_mod_eqq(node, recv, arg, merge)
          else
            gated = @f.label
            @f.brif(gate_clear("GATE_IS_A"), gated, @inline.bail)
            switch(gated)
            is_a_in_place(class_of(recv), arg, merge, @inline.bail)
          end
        end

        # `Mod === x` through the def's own cell, if the cell has
        # Module#=== and the receiver is a ranked class.
        def spec_mod_eqq(node, recv, arg, merge)
          cc = site_cache(node, "ic", "CallCache", Sends::CALL_WAYS)
          cell = @l.layout("CallCache")
          heap = @f.label
          hit = @f.label
          shaped = @f.label
          @f.brif(cellp(recv), heap, @inline.bail)
          switch(heap)
          @f.brif(cell_hit(cc, @f.fetch("i64", recv, off(@l.layout("RBasic"), "klass"))), hit, @inline.bail)
          switch(hit)
          held = @f.icmp("eq", @f.fetch("i64", cc, off(cell, "shape")), imm(@l.const("SHAPE_MOD_EQQ")))
          @f.brif(@f.band(held, ranked?(recv)), shaped, @inline.bail)
          switch(shaped)
          is_a_in_place(class_of(arg), recv, merge, @inline.bail)
        end

        def spec_identity(node, recv, arg, merge)
          cc = site_cache(node, "ic", "CallCache", Sends::CALL_WAYS)
          cell = @l.layout("CallCache")
          hit = @f.label
          shaped = @f.label
          @f.brif(cell_hit(cc, class_of(recv)), hit, @inline.bail)
          switch(hit)
          shape = node.name == :== ? "SHAPE_EQ" : "SHAPE_NE"
          @f.brif(@f.icmp("eq", @f.fetch("i64", cc, off(cell, "shape")), imm(@l.const(shape))), shaped, @inline.bail)
          switch(shaped)
          @f.jump(merge, [ruby_bool(@f.icmp(node.name == :== ? "eq" : "ne", recv, arg))])
        end

        # Whether `cc`'s first way has `klass` at the site stamp.
        def cell_hit(cc, klass)
          cell = @l.layout("CallCache")
          @f.band(@f.icmp("eq", klass, @f.fetch("i64", cc, off(cell, "klass"))),
                  @f.icmp("eq", @f.fetch("i64", cc, off(cell, "stamp")), @f.fetch("i64", static("site_stamp"))))
        end

        # Whether `v` is a cell: a pointer past the special constants.
        def cellp(v)
          @f.band(@f.icmp("eq", @f.band(v, imm(7)), imm(0)), @f.icmp("ugt", v, @qnil))
        end
      end
    end
  end
end
