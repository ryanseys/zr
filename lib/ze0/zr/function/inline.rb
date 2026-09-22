# frozen_string_literal: true

module Ze0
  module Zr
    class Function
      # A small def of the unit, inlined at a site that calls it.
      #
      # The site keeps its cell and its class-and-stamp test; on a hit
      # whose direct entry is the def's own body, the body runs here
      # with no frame, in a form where every guard that fails -- a cell
      # that misses, a receiver of another kind, an operator past the
      # fixnums, a gate closed -- jumps to `bail`: the ordinary call,
      # which runs the def from its start. So the copy may hold only
      # what leaves nothing behind: reads of parameters, of self's ivars
      # through their guessed rows, of readers and type questions
      # through the cells the def's own sites use, fixnum arithmetic,
      # branches and a return. No call, no store, no allocation. The
      # def's own function keeps its cells with the copy (`site_cell`),
      # so a bail that runs the def fills what the copy reads next time.
      #
      # What a program observes: no frame for the inlined def, so no
      # SystemStackError from it and one entry poll fewer; a backtrace
      # is never taken inside the copy, since nothing in it raises.
      module Inline
        # The most HIR nodes a candidate's body may hold.
        LIMIT = 24
        # The one-argument sends a copy answers: an Integer operator on
        # fixnums, identity for BasicObject's `==`/`!=`, a type question,
        # a `case` arm over a class.
        ARGUED = %i[is_a? kind_of? ===].freeze
        # A name a reader may have.
        READER = /\A[a-z_][A-Za-z0-9_]*\z/

        # The defs of `body`, a unit's tree, that a site may inline, by
        # name: written once in the unit, required positionals alone
        # (four at most, the direct entry's shape), no other local, and
        # a body of the nodes `pure?` takes. A def with a receiver
        # (`def self.x`) counts against the name and is never one.
        def self.candidates(body)
          defs = Hash.new { |h, k| h[k] = [] }
          each_def(body) { |d| defs[d.name] << d }
          defs.each_with_object({}) do |(name, list), out|
            d = list.first
            next unless list.size == 1 && d.receiver.nil? && d.params.plain? && d.params.required.size <= DIRECT_ARGS
            next unless d.params.required.all?(Symbol) && d.locals == d.params.required && d.params.block.nil?

            out[name] = d if pure?(d.body, [d.params.required.size + 1])
          end
        end

        # Every Def under `node`, at any depth: class bodies, blocks and
        # the defs themselves are walked into.
        def self.each_def(node, &blk)
          case node
          when Hir::Def
            yield node
            each_def(node.body, &blk)
          when Hir::Seq then node.stmts.each { |n| each_def(n, &blk) }
          when Hir::ClassDef, Hir::ModuleDef, Hir::SingletonClassDef then each_def(node.body, &blk)
          when Hir::If
            each_def(node.cond, &blk)
            each_def(node.yes, &blk) if node.yes
            each_def(node.no, &blk) if node.no
          when Hir::While
            each_def(node.cond, &blk)
            each_def(node.body, &blk)
          when Hir::Send
            each_def(node.recv, &blk) if node.recv
            node.args.each { |a| each_def(a, &blk) }
            each_def(node.block.body, &blk) if node.block.is_a?(Hir::Block)
          when Hir::Begin
            each_def(node.body, &blk) if node.body
          end
        end

        # Whether `node` is of the form a copy lowers, counting its nodes
        # into `count` (a one-element Array, the running total).
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

        # A send with an explicit receiver and no block, keywords, splat
        # or refinement: a reader or `nil?` of no argument, or one of
        # the argued forms.
        def self.pure_send?(node, count)
          return false if node.recv.nil? || node.vcall || node.block || node.kwargs || node.safe || node.using || node.write
          return false unless pure?(node.recv, count) && node.args.all? { |a| !a.is_a?(Hir::Splat) && pure?(a, count) }

          case node.args.size
          when 0 then node.name == :nil? || node.name.match?(READER)
          when 1 then Sends::OPS.key?(node.name) || ARGUED.include?(node.name)
          else false
          end
        end

        private

        # The def a call of `node` may inline, where the site's shape
        # allows one: its count the def's, no block, no keywords, no
        # splat, not under `using`, not traced (a trace sees every
        # frame), not in the core (whose sends carry their own modes).
        def inline_candidate(node)
          return nil if traced? || @l.internal? || node.block || node.kwargs || node.using || node.args.any?(Hir::Splat)

          d = @l.inline_def(node.name)
          d if d && d.params.required.size == node.args.size
        end

        # The copy of `d`'s body at the site, with `recv` as its self and
        # `given` its parameters; every guard that fails jumps to `bail`.
        # Answers the body's value.
        def inline_body(d, recv, given, bail)
          exit, (result,) = @f.block(["i64"])
          saved = [@self, @inline_locals, @inline_exit, @inline_bail, @inlining]
          @self = recv
          @inline_locals = d.params.required.zip(given).to_h
          @inline_exit = exit
          @inline_bail = bail
          @inlining = true
          v = spec(d.body)
          @f.jump(exit, [v]) unless @f.terminated?
          @self, @inline_locals, @inline_exit, @inline_bail, @inlining = saved
          switch(exit)
          result
        end

        # The value of `node` in the copy: `expr` for the nodes `pure?`
        # took, with every miss a jump to the bail block.
        def spec(node)
          case node
          when Hir::Seq then spec_seq(node)
          when Hir::If then spec_branch(node)
          when Hir::And, Hir::Or then spec_logical(node)
          when Hir::Not then spec_negate(node)
          when Hir::Return then spec_return(node)
          when Hir::Literal then literal(node)
          when Hir::SelfRef then @self
          when Hir::Local then @inline_locals.fetch(node.name)
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

        def spec_jump_if(node, yes, no)
          case node
          when Hir::And, Hir::Or
            rest = @f.label
            node.is_a?(Hir::And) ? spec_jump_if(node.left, rest, no) : spec_jump_if(node.left, yes, rest)
            switch(rest)
            spec_jump_if(node.right, yes, no)
          else
            v = spec(node)
            @f.brif(truthy(v), yes, no) unless @f.terminated?
          end
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

        # `!v` for nil, true and false under GATE_NOT (`Sends#negate`);
        # any other receiver bails.
        def spec_negate(node)
          v = spec(node.value)
          go = @f.label
          boolean = @f.icmp("eq", @f.bor(v, imm(28)), imm(28))
          @f.brif(@f.band(boolean, gate_clear("GATE_NOT")), go, @inline_bail)
          switch(go)
          @f.csel(truthy(v), imm(@l.const("QFALSE")), imm(@l.const("QTRUE")))
        end

        def spec_return(node)
          v = node.value ? spec(node.value) : @qnil
          @f.jump(@inline_exit, [v]) unless @f.terminated?
          @qnil
        end

        # `@name` of the copy's self through the def's own guessed row.
        def spec_ivar_read(node)
          ivar = ivar_name(node.name)
          ic = site_cache(node, "iv", "IvarCache")
          row = guessed_ivar_row(ic, ivar, @inline_bail, writing: false)
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
        # in Object's family, which Kernel's answer holds for).
        def spec_nil_p(recv, merge)
          is_nil = @f.label
          not_nil = @f.label
          ranked = @f.label
          @f.brif(gate_clear("GATE_NIL_P"), is_nil, @inline_bail)
          switch(is_nil)
          @f.brif(@f.icmp("eq", recv, @qnil), not_nil, ranked)
          switch(not_nil)
          @f.jump(merge, [imm(@l.const("QTRUE"))])
          switch(ranked)
          answer = @f.label
          @f.brif(ranked?(class_of(recv)), answer, @inline_bail)
          switch(answer)
          @f.jump(merge, [imm(@l.const("QFALSE"))])
        end

        # A reader through the def's own cell: a cell receiver whose
        # class the cell holds at the site stamp, with a reader's shape,
        # read in place; anything else bails.
        def spec_reader(node, recv, merge)
          cc = site_cache(node, "ic", "CallCache", Sends::CALL_WAYS)
          cell = @l.layout("CallCache")
          heap = @f.label
          hit = @f.label
          shaped = @f.label
          @f.brif(cellp(recv), heap, @inline_bail)
          switch(heap)
          klass = @f.fetch("i64", recv, off(@l.layout("RBasic"), "klass"))
          @f.brif(cell_hit(cc, klass), hit, @inline_bail)
          switch(hit)
          @f.brif(@f.icmp("eq", @f.fetch("i64", cc, off(cell, "shape")), imm(@l.const("SHAPE_READER"))), shaped, @inline_bail)
          switch(shaped)
          accessor_in_place(:reader, recv, @f.fetch("i64", cc, off(cell, "entry")), nil, merge, @inline_bail)
        end

        # An operator on two fixnums under its gate; `==` and `!=` by
        # identity where the def's own cell holds BasicObject's; a type
        # question by the classes. Anything else bails.
        def spec_argued(node, recv, arg, merge)
          op = node.name
          if Sends::OPS.key?(op)
            fixnums = @f.label
            rest = @f.label
            both = @f.icmp("ne", @f.band(@f.band(recv, arg), imm(1)), imm(0))
            @f.brif(@f.band(both, gate_clear(Sends::OPS.fetch(op))), fixnums, rest)
            switch(fixnums)
            @f.jump(merge, [fast_path(op, recv, arg, @inline_bail)])
            switch(rest)
            return spec_identity(node, recv, arg, merge) if %i[== !=].include?(op)

            @f.jump(@inline_bail)
          elsif op == :===
            spec_mod_eqq(node, recv, arg, merge)
          else
            gated = @f.label
            @f.brif(gate_clear("GATE_IS_A"), gated, @inline_bail)
            switch(gated)
            is_a_in_place(class_of(recv), arg, merge, @inline_bail)
          end
        end

        # `Mod === x` through the def's own cell, where the cell holds
        # Module#=== and the receiver is a ranked class.
        def spec_mod_eqq(node, recv, arg, merge)
          cc = site_cache(node, "ic", "CallCache", Sends::CALL_WAYS)
          cell = @l.layout("CallCache")
          heap = @f.label
          hit = @f.label
          shaped = @f.label
          @f.brif(cellp(recv), heap, @inline_bail)
          switch(heap)
          @f.brif(cell_hit(cc, @f.fetch("i64", recv, off(@l.layout("RBasic"), "klass"))), hit, @inline_bail)
          switch(hit)
          held = @f.icmp("eq", @f.fetch("i64", cc, off(cell, "shape")), imm(@l.const("SHAPE_MOD_EQQ")))
          @f.brif(@f.band(held, ranked?(recv)), shaped, @inline_bail)
          switch(shaped)
          is_a_in_place(class_of(arg), recv, merge, @inline_bail)
        end

        def spec_identity(node, recv, arg, merge)
          cc = site_cache(node, "ic", "CallCache", Sends::CALL_WAYS)
          cell = @l.layout("CallCache")
          hit = @f.label
          shaped = @f.label
          @f.brif(cell_hit(cc, class_of(recv)), hit, @inline_bail)
          switch(hit)
          shape = node.name == :== ? "SHAPE_EQ" : "SHAPE_NE"
          @f.brif(@f.icmp("eq", @f.fetch("i64", cc, off(cell, "shape")), imm(@l.const(shape))), shaped, @inline_bail)
          switch(shaped)
          @f.jump(merge, [ruby_bool(@f.icmp(node.name == :== ? "eq" : "ne", recv, arg))])
        end

        # Whether `cc`'s first way holds `klass` at the site stamp.
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
