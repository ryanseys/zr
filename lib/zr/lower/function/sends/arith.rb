# frozen_string_literal: true

# `Sends` for the operators: fixnum and flonum fast paths under
# their gates, and the call when a gate is set.

module Zr
  class Lower
    class Function
      module Sends
        # @type instance: Function

        private

        # An Integer operator: the inline fixnum fast path if both sides
        # are fixnums and the gate is clear, else the call. Equality also
        # uses the call for other operands: `1 == 1.0` is true, and
        # `1 == obj` sends `obj == 1`.
        #: (Hir::Send node, String recv, String? argv, ?String? arg) ?{ () -> String } -> String
        def operator(node, recv, argv, arg = nil)
          # `argv` is nil only when the caller gives `arg` and the block.
          given = argv #: String
          arg ||= @f.fetch("i64", given)
          ok = @f.band(fixnums?(recv, arg), gate_clear(OPS.fetch(node.name)))
          fast = @f.label
          slow = @f.cold(@f.label)
          floating = @f.label if float_path?(node)
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(ok, fast, floating || slow)
          switch(fast)
          value = fast_path(node.name, recv, arg, slow)
          @f.jump(merge, [value])
          if floating
            switch(floating)
            @f.jump(merge, [float_path(node.name, recv, arg, slow)])
          end
          switch(slow)
          native_equality(node, recv, arg) { |equal| @f.jump(merge, [ruby_bool(equal)]) }
          @f.jump(merge, [block_given? ? yield : dispatch(node, recv, given, imm(1))])
          switch(merge)
          result
        end

        # In the core library, `==` and `!=` answer natively for the values
        # that CRuby's C compares natively (zr_native_eq_kind). The block
        # takes the answer as a condition, and the send follows for all
        # other operands.
        #: (Hir::Send node, String recv, String arg) { (String) -> void } -> void
        def native_equality(node, recv, arg)
          return unless native_operators? && %i[== !=].include?(node.name)

          kind = kernel("zr_native_eq_kind", recv, arg)
          answered = @f.label
          sent = @f.label
          @f.brif(@f.icmp("ne", kind, imm(0)), answered, sent)
          switch(answered)
          yield @f.icmp(node.name == :== ? "eq" : "ne", kind, imm(1))
          switch(sent)
        end

        # In the core library, `<=>` of two fixnums answers natively while
        # Integer#<=> is ruby's own, as CRuby's OPTIMIZED_CMP does. All
        # other operands send it.
        #: (Hir::Send node, String recv, String argv) -> String
        def native_compare(node, recv, argv)
          arg = @f.fetch("i64", argv)
          fast = @f.label
          slow = @f.cold(@f.label)
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          own = @f.icmp("eq", @f.band(@f.gates, imm(@l.const("GATE_CMP"))), imm(0))
          @f.brif(@f.band(fixnums?(recv, arg), own), fast, slow)
          switch(fast)
          less = @f.icmp("slt", recv, arg)
          more = @f.icmp("sgt", recv, arg)
          @f.jump(merge, [@f.csel(less, imm(-1), @f.csel(more, imm(3), imm(1)))])
          switch(slow)
          @f.jump(merge, [dispatch(node, recv, argv, imm(1))])
          switch(merge)
          result
        end

        # `recv.succ` and `-recv` on a fixnum while Integer's method is not
        # redefined: the sum or the difference inline. Outside the fixnums
        # or after a redefinition, the call. `bm_ruby_xor` counts with
        # `i.succ`, so this removes a send per iteration.
        #
        # `-recv` on a flonum while Float's `-@` is not redefined flips the
        # sign, which a flonum keeps at bit 2. Two flonums use the call:
        # +0.0, whose negation is not a flonum, and the one whose negation
        # is the double that the flonum zero's bit pattern replaces
        # (`float_value`). The two differ only in that bit.
        #: (Hir::Send node, String recv, String? argv) ?{ () -> String } -> String
        def unary(node, recv, argv)
          # `argv` is nil only when the caller gives the block.
          given = argv #: String
          fix = @f.icmp("ne", @f.band(recv, imm(1)), imm(0))
          ok = @f.band(fix, gate_clear(UNARY.fetch(node.name)))
          fast = @f.label
          slow = @f.cold(@f.label)
          floating = @f.label if FLOAT_UNARY.key?(node.name)
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(ok, fast, floating || slow)
          switch(fast)
          value = node.name == :succ ? @f.sadd_overflow(recv, imm(2)) : @f.ssub_overflow(imm(2), recv)
          @f.jump(merge, [overflow_or(value, slow)])
          if floating
            negated = @f.label
            switch(floating)
            flips = @f.band(flonum?(recv), @f.icmp("ne", @f.band(recv, imm(~4)), imm(FLONUM_ZERO)))
            @f.brif(@f.band(flips, gate_clear(FLOAT_UNARY.fetch(node.name))), negated, slow)
            switch(negated)
            @f.jump(merge, [@f.bxor(recv, imm(4))])
          end
          switch(slow)
          @f.jump(merge, [block_given? ? yield : dispatch(node, recv, given, imm(0))])
          switch(merge)
          result
        end

        # Whether the site gets the flonum path (`float_path`), which is
        # about forty instructions: an operator that has one, unless an
        # operand is an Integer literal in a sum, a difference or a
        # comparison. Those count and index much more often than they get
        # a Float (`x * 2` and `x / 2` keep the path).
        #: (Hir::Send node) -> bool
        def float_path?(node)
          return false unless FLOAT_OPS.key?(node.name)
          return true if %i[* /].include?(node.name)

          [node.recv, node.args.first].none? { |n| n.is_a?(Hir::Literal) && n.value.is_a?(Integer) }
        end

        # The flonum path: both operands are flonums, or one is a flonum
        # and the other a fixnum (within 2^53 for a comparison, which ruby
        # does exactly), and the operator's Integer and Float gates are
        # clear. The arithmetic is on doubles, and the result is a flonum
        # or the kernel's heap Float. A comparison is as in ruby (false with
        # a NaN). All other cases go to `slow`.
        #: (Symbol op, String a, String b, String slow) -> String
        def float_path(op, a, b, slow)
          fop = FLOAT_OPS.fetch(op).first
          x, y = doubles(op, a, b, slow)
          fop.is_a?(String) ? ruby_bool(@f.fcmp(fop, x, y)) : float_value(@f.fbinop(fop, x, y))
        end

        # The operands of `op` as doubles, if the flonum path accepts them.
        # Else the branch to `slow`. Each operand is a Value or an Operand.
        #: (Symbol op, String | Operand a, String | Operand b, String slow) -> [String, String]
        def doubles(op, a, b, slow)
          a = Operand.new(a, nil) unless a.is_a?(Operand)
          b = Operand.new(b, nil) unless b.is_a?(Operand)
          fop, gate = FLOAT_OPS.fetch(op)
          compare = fop.is_a?(String)
          go = @f.label
          numbers = @f.band(number_operand?(a, compare), number_operand?(b, compare))
          some_flonum = @f.bor(float_operand?(a), float_operand?(b))
          gates = gates_clear(OPS.fetch(op), gate)
          @f.brif(@f.band(@f.band(numbers, some_flonum), gates), go, slow)
          switch(go)
          [operand_double(a), operand_double(b)]
        end

        # An operand of a float operator. `bits` is nil for a plain Value.
        # Else the operand is an inner float operator's result
        # (`unboxed_operator`): `value` is QUNDEF when the inner operator
        # took its flonum path, and then `bits` holds the double, which no
        # code boxes unless the outer operator sends.
        # @rbs skip -- typed in sig/zr/lower/function/sends/arith.rbs
        Operand = Data.define(:value, :bits)

        # Whether the operand holds its double in `bits`.
        #: (Operand o) -> String
        def unboxed?(o) = @f.icmp("eq", o.value, qundef)

        #: (Operand o, bool exact) -> String
        def number_operand?(o, exact)
          o.bits ? @f.bor(unboxed?(o), number?(o.value, exact)) : number?(o.value, exact)
        end

        #: (Operand o) -> String
        def float_operand?(o)
          o.bits ? @f.bor(unboxed?(o), flonum?(o.value)) : flonum?(o.value)
        end

        #: (Operand o) -> String
        def operand_double(o)
          return as_double(o.value) unless o.bits

          @f.bitcast("f64", @f.csel(unboxed?(o), o.bits, double_bits(o.value)))
        end

        # The operand as a Value: an unboxed double becomes a Float.
        #: (Operand o) -> String
        def boxed(o)
          return o.value unless o.bits

          box = @f.label
          keep = @f.label
          merge, (v,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(unboxed?(o), box, keep)
          switch(box)
          @f.jump(merge, [float_value(@f.bitcast("f64", o.bits))])
          switch(keep)
          @f.jump(merge, [o.value])
          switch(merge)
          v
        end

        # Whether `node`, as an operand of a float operator, can give its
        # result as a double: an arithmetic float operator that lowers
        # through `direct_operator`.
        #: (Hir::node? node) -> bool
        def unboxable?(node)
          node.is_a?(Hir::Send) && !node.safe && !node.interp && FLOAT_OPS.key?(node.name) &&
            !FLOAT_OPS.fetch(node.name).first.is_a?(String) && float_path?(node) && !primitive?(node) &&
            direct_operands?(node, node.recv || Hir::SelfRef.new(node.line))
        end

        # An operand of the operator `node`: an inner float operator
        # unboxed if `node` has the flonum path, else the plain Value.
        # Equality in the core library answers natively first
        # (`native_equality`), so it keeps its Values.
        #: (Hir::Send node, Hir::node? operand) -> Operand
        def operand_of(node, operand)
          fused = float_path?(node) && !(native_operators? && %i[== !=].include?(node.name))
          return Operand.new(expr(operand), nil) unless fused && operand.is_a?(Hir::Send) && unboxable?(operand)

          unboxed_operator(operand)
        end

        # A float operator whose result goes to an outer float operator.
        #: (Hir::Send node) -> Operand
        def unboxed_operator(node)
          a, b = site_operands(node, node.recv || Hir::SelfRef.new(node.line))
          fused_operator(node, a, b, unboxed: true).tap { deactivate(node) }
        end

        # The send of an operator with Operands. Both go into their slots
        # first, so a Float that boxes one cannot free the other, then each
        # double is boxed in its slot.
        #: (Hir::Send node, Operand a, Operand b) -> String
        def sent_fused(node, a, b)
          base = reserve(2)
          [a, b].each_with_index { |o, i| @f.store(o.value, @rec, value_offset(base + i)) }
          [a, b].each_with_index { |o, i| @f.store(boxed(o), @rec, value_offset(base + i)) if o.bits }
          slots = @f.iadd(@rec, imm(value_offset(base)))
          result = dispatch(node, @f.fetch("i64", slots), @f.iadd(slots, imm(8)), imm(1))
          release(base)
          result
        end

        # `operator` with Operands. With `unboxed`, the result is an
        # Operand, and its flonum path gives the double; else it is a
        # Value.
        #: (Hir::Send node, Operand a, Operand b, unboxed: false) -> String
        #: (Hir::Send node, Operand a, Operand b, unboxed: true) -> Operand
        def fused_operator(node, a, b, unboxed:)
          op = node.name
          fop = FLOAT_OPS.fetch(op).first
          fast = @f.label
          slow = @f.cold(@f.label)
          floating = @f.label
          # `bits` is set and read only when `unboxed`.
          merge, (result, bits) = @f.block(unboxed ? %w[i64 i64] : ["i64"]) #: [String, [String, String]]
          tail = unboxed ? [imm(0)] : [] #: Array[String]
          @f.brif(@f.band(fixnums?(a.value, b.value), gate_clear(OPS.fetch(op))), fast, floating)
          switch(fast)
          @f.jump(merge, [fast_path(op, a.value, b.value, slow), *tail])
          switch(floating)
          x, y = doubles(op, a, b, slow)
          if fop.is_a?(String)
            @f.jump(merge, [ruby_bool(@f.fcmp(fop, x, y))])
          elsif unboxed
            @f.jump(merge, [qundef, @f.bitcast("i64", @f.fbinop(fop, x, y))])
          else
            @f.jump(merge, [float_value(@f.fbinop(fop, x, y))])
          end
          switch(slow)
          @f.jump(merge, [sent_fused(node, a, b), *tail])
          switch(merge)
          unboxed ? Operand.new(result, bits) : result
        end

        #: (String a, String b) -> String
        def fixnums?(a, b) = @f.icmp("ne", @f.band(@f.band(a, b), imm(1)), imm(0))

        #: (String v) -> String
        def flonum?(v) = @f.icmp("eq", @f.band(v, imm(3)), imm(2))

        # Whether `v` is a flonum or a fixnum. When `exact`, the fixnum must
        # be within 2^53 in both directions.
        #: (String v, bool exact) -> String
        def number?(v, exact)
          fix = @f.icmp("ne", @f.band(v, imm(1)), imm(0))
          fix = @f.band(fix, @f.icmp("ult", @f.iadd(@f.sshr(v, imm(1)), imm(1 << 53)), imm(1 << 54))) if exact
          @f.bor(flonum?(v), fix)
        end

        # The double value of a flonum or fixnum `v`: `zr_float_value`'s
        # rotation, +0.0 for the flonum zero, or a converted fixnum.
        #: (String v) -> String
        def as_double(v) = @f.bitcast("f64", double_bits(v))

        # The bits of `as_double`'s result.
        #: (String v) -> String
        def double_bits(v)
          sign = @f.ushr(v, imm(63))
          x = @f.bor(@f.isub(imm(2), sign), @f.band(v, imm(-4)))
          rotated = @f.bor(@f.ushr(x, imm(3)), @f.ishl(x, imm(61)))
          decoded = @f.csel(@f.icmp("eq", v, imm(FLONUM_ZERO)), imm(0), rotated)
          converted = @f.bitcast("i64", @f.fcvt_from_sint(@f.sshr(v, imm(1))))
          @f.csel(flonum?(v), decoded, converted)
        end

        # `zr_float_new` inline: a flonum if the exponent's top bits are
        # 011 or 100, the flonum zero for +0.0, else the kernel's cell.
        #: (String d) -> String
        def float_value(d)
          b = @f.bitcast("i64", d)
          top = @f.band(@f.ushr(b, imm(60)), imm(7))
          fits = @f.band(@f.icmp("ne", b, imm(FLONUM_HOLE)), @f.icmp("ult", @f.isub(top, imm(3)), imm(2)))
          rotated = @f.bor(@f.ishl(b, imm(3)), @f.ushr(b, imm(61)))
          flonum = @f.bor(@f.band(rotated, imm(-2)), imm(2))
          rotate = @f.label
          other = @f.label
          zero = @f.label
          heap = @f.label
          merge, (v,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(fits, rotate, other)
          switch(rotate)
          @f.jump(merge, [flonum])
          switch(other)
          @f.brif(@f.icmp("eq", b, imm(0)), zero, heap)
          switch(zero)
          @f.jump(merge, [imm(FLONUM_ZERO)])
          switch(heap)
          @f.jump(merge, [kernel("zr_float_new", d)])
          switch(merge)
          v
        end

        # The tagged result of `op` on tagged fixnums `a` and `b`. A result
        # outside the fixnum range goes to `slow`.
        #: (Symbol op, String a, String b, String slow) -> String
        def fast_path(op, a, b, slow)
          one = imm(1)
          case op
          when :+ then overflow_or(@f.sadd_overflow(a, @f.isub(b, one)), slow)
          when :- then @f.bor(overflow_or(@f.ssub_overflow(a, b), slow), one)
          when :* then @f.bor(overflow_or(@f.smul_overflow(@f.sshr(a, one), @f.isub(b, one)), slow), one)
          when :/, :%
            # -2^62 / -1 is outside the fixnum range, so that pair uses the
            # call.
            x = @f.sshr(a, one)
            y = @f.sshr(b, one)
            unless_equal(y, 0, slow)
            unless_equal(y, -1, slow) if op == :/
            @f.bor(@f.ishl(floored(op, x, y), one), one)
          when :& then @f.band(a, b)
          when :| then @f.bor(a, b)
          when :^ then @f.bor(@f.bxor(a, b), one)
          when :>>
            # A shift of 63 or more, or a negative count, is not a right
            # shift of a fixnum, so it uses the call.
            k = @f.sshr(b, one)
            unless_unsigned_below(k, 63, slow)
            @f.bor(@f.sshr(a, k), one)
          when *RELATIONS.keys then ruby_bool(@f.icmp(RELATIONS.fetch(op), a, b))
          end #: String
        end

        # A negative count is a very large unsigned value, so one branch
        # checks both ends of the range.
        #: (String value, Integer n, String escape) -> void
        def unless_unsigned_below(value, n, escape)
          ok = @f.label
          @f.brif(@f.icmp("uge", value, imm(n)), escape, ok)
          switch(ok)
        end

        # `x / y` or `x % y` rounded toward minus infinity, for `y` not 0.
        # If neither is negative, the machine's truncation gives the same
        # result. Else use the kernel's floor.
        #: (Symbol op, String x, String y) -> String
        def floored(op, x, y)
          same = @f.label
          call = @f.label
          merge, (q,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(@f.icmp("sge", @f.bor(x, y), imm(0)), same, call)
          switch(same)
          @f.jump(merge, [op == :/ ? @f.sdiv(x, y) : @f.srem(x, y)])
          switch(call)
          @f.jump(merge, [kernel(op == :/ ? "zr_floor_div" : "zr_floor_mod", x, y)])
          switch(merge)
          q
        end

        #: (String value, Integer n, String escape) -> void
        def unless_equal(value, n, escape)
          ok = @f.label
          @f.brif(@f.icmp("eq", value, imm(n)), escape, ok)
          switch(ok)
        end

        # No annotation: Steep cannot type a destructured parameter.
        def overflow_or((value, flag), slow)
          ok = @f.label
          @f.brif(flag, slow, ok)
          switch(ok)
          value
        end

        #: (String name) -> String
        def gate_clear(name) = gates_clear(name)

        # Whether the fast paths ignore the gates. The core library and
        # the compiler that eval carries are ruby's C, which compares and
        # counts its own values natively whatever a program redefines. A
        # method that CRuby writes in Ruby (`:ruby`) sends as Ruby does, and
        # so does one whose C sends its operators by name (`:sends_ops`).
        #: () -> bool
        def native_operators?
          # Nil only until the first call sets it.
          known = @native_operators
          return known unless known.nil?

          fn = self #: Function
          # The walk stops at the first scope that is not a block, so it
          # never reaches an eval's Outer.
          while fn.kind == :block && (up = fn.outer).is_a?(Function)
            fn = up
          end
          # False, not nil, for a program's code, so the memo holds.
          @native_operators = @l.internal? || @l.support? ? !fn.attributes.intersect?(%i[ruby sends_ops sends_all]) : false
        end

        # Whether `each` finds the core's own method. Ruby's C walks its
        # own Arrays and Hashes directly, and sends `each` by name only in
        # Enumerable (Primitive.zr_enum_each) and where a def is marked
        # `:sends_each`: rb_block_call(obj, id_each) in the Lazy and Chain
        # enumerators, zip of an enumerable and Range#first, and the few
        # methods that CRuby writes in Ruby with an `each` of their own
        # (Pathname, Ractor.select). A `:ruby` method alone, such as
        # Kernel#warn, has a C body behind its Ruby signature.
        #: () -> bool
        def native_each?
          # Nil only until the first call sets it.
          known = @native_each
          return known unless known.nil?

          fn = self #: Function
          # The walk stops at the first scope that is not a block, so it
          # never reaches an eval's Outer.
          while fn.kind == :block && (up = fn.outer).is_a?(Function)
            fn = up
          end
          @native_each = @l.internal? || @l.support? ? !fn.attributes.intersect?(%i[sends_each sends_all]) : false
        end

        # Whether the code stands in for CRuby's C: the core library or
        # eval's compiler, outside the defs that CRuby writes in Ruby.
        #: () -> bool
        def c_stand_in?
          (@l.internal? || @l.support?) && !sends_all?
        end

        # Whether the def is one that CRuby writes in Ruby alone
        # (`:sends_all`), so its every send goes by name, as Ruby's do.
        #: () -> bool
        def sends_all?
          # Nil only until the first call sets it.
          known = @sends_all
          return known unless known.nil?

          fn = self #: Function
          while fn.kind == :block && (up = fn.outer).is_a?(Function)
            fn = up
          end
          @sends_all = fn.attributes.include?(:sends_all)
        end

        # Whether all the given gates are clear: one test of the gate word,
        # from its register.
        #: (*String names) -> String
        def gates_clear(*names)
          return @f.icmp("eq", imm(0), imm(0)) if native_operators?

          gate_test(names)
        end

        # The gate of an inline `each` over an Array or a Range, which a
        # def marked `:sends_each` keeps (`native_each?`).
        #: (String name) -> String
        def each_gate_clear(name)
          return @f.icmp("eq", imm(0), imm(0)) if native_each?

          gate_test([name])
        end

        #: (Array[String] names) -> String
        def gate_test(names)
          @f.icmp("eq", @f.band(@f.gates, imm(names.sum { |name| @l.const(name) })), imm(0))
        end

        # `!v` inline for nil, true and false while none of their classes
        # redefines `!` (GATE_NOT). All other receivers send `!` through
        # the site's own cell, as a call does. The three are the only
        # Values below 28 with their low two bits clear. In the core's
        # stand-ins for C, `!v` is CRuby's !RTEST(v), which sends nothing.
        #: (Hir::Not node) -> String
        def negate(node)
          staged([node.value]) do |slots, base|
            v = @f.fetch("i64", @rec, value_offset(base))
            next @f.csel(truthy(v), imm(@l.const("QFALSE")), imm(@l.const("QTRUE"))) if c_stand_in?

            fast = @f.label
            slow = @f.label
            merge, (result,) = @f.block(["i64"]) #: [String, [String]]
            boolean = @f.icmp("eq", @f.bor(v, imm(28)), imm(28))
            @f.brif(@f.band(boolean, gate_clear("GATE_NOT")), fast, slow)
            switch(fast)
            @f.jump(merge, [@f.csel(truthy(v), imm(@l.const("QFALSE")), imm(@l.const("QTRUE")))])
            switch(slow)
            send = @l.noted(Hir::Send.of(node.value, :!, [], node.line), node)
            @f.jump(merge, [dispatch(send, v, @f.iadd(slots, imm(8)), imm(0))])
            switch(merge)
            result
          end
        end
      end
    end
  end
end
