# frozen_string_literal: true

require_relative "../prism"
require_relative "../ir"
require_relative "../refused"
require_relative "../paths"
require_relative "description"

module Zr
  module Machine
    # Lowers one machine def to one IR function. A def that can run the
    # collector keeps a root frame in its frame: `prev, n, values...`.
    # The root frame links from the static head of the unit and contains
    # each Value of the def (a parameter, a local, or the result of a call
    # that goes to another call). Thus a collection in any call sees them all.
    class Function
      def initialize(unit, d)
        @unit = unit
        @d = d
        @f = IR::Function.new(d.name, d.params.map { |_, t| TYPES.fetch(t) }, TYPES.fetch(d.ret))
        @locals = {}
        @loops = []
        @roots = nil
        @inlining = [d.name]
        # The target of a `return` in an inlined body: the block after
        # the body, made by the first `return`. Nil in the def's own body.
        @exit = nil
      end

      def lower
        enter_roots if @unit.collects?(@d.name)
        @d.params.each_with_index do |(name, type), i|
          local = declare_local(@d.node, name, type)
          @f.store(@f.args[i], local[:addr])
        end
        body = @d.node.body
        value, type = body ? statements(body, @d.ret) : [nil, "Void"]
        unless @f.terminated?
          refuse(@d.node, "the body ends in #{type}, and the sig says #{@d.ret}") unless @d.ret == "Void" || fits?(@d.ret, type)
          ret(@d.ret == "Void" ? nil : value)
        end
        leave_roots if @roots
        IR::Mem2Reg.run(@f)
      end

      # Links in the root frame before the body. `leave_roots` sets the
      # slot count and the zero fill after the body has made all slots.
      def enter_roots
        slot = @f.slot(16)
        @roots = { slot: slot, addr: @f.stack_addr(slot), n: 0, zero: @f.iconst("i64", 0) }
        @head = @f.symbol_value(@f.symbol("zr_static_#{Lower::ROOTS}"))
        @f.store(@f.fetch("i64", @head), @roots[:addr], 0)
        count, @roots[:count] = @f.iconst_later("i64")
        @f.store(count, @roots[:addr], 8)
        @f.store(@roots[:addr], @head, 0)
        @roots[:fill_at] = @f.entry_block.insts.size
      end

      def leave_roots
        n = @roots[:n]
        @roots[:count].args[0] = n
        @f.slots[@roots[:slot].delete_prefix("ss").to_i].bytes = 16 + (8 * n)
        fill = (0...n).map { |i| IR::Inst.new(:store, args: [@roots[:zero], @roots[:addr]], offset: 16 + (8 * i), flags: "notrap aligned") }
        @f.entry_block.insts.insert(@roots[:fill_at], *fill)
      end

      # The offset of a new root slot.
      def root_slot
        at = 16 + (8 * @roots[:n])
        @roots[:n] += 1
        at
      end

      # `return`: first unlinks the root frame. In an inlined body, a
      # return is a jump with the value to the block after the body,
      # because a `ret` there would return from the caller.
      def ret(value)
        return @f.jump(inline_exit, [value].compact) if @exit

        @f.store(@f.fetch("i64", @roots[:addr]), @head, 0) if @roots
        @f.ret(value)
      end

      # The block that all returns of an inlined body jump to. Its
      # parameter is the returned value.
      def inline_exit
        @exit[:block] ||= begin
          block, params = @exit[:type] == "Void" ? @f.block : @f.block([ir_type(@exit[:type])])
          @exit[:value] = params.first
          block
        end
      end

      private

      def refuse(node, message)
        raise Refused.new(node, message, @unit.unit? ? @d.file : nil)
      end

      # A local is in a slot of its own. A Value in a rooted function is
      # in the root frame.
      def declare_local(node, name, type)
        refuse(node, "#{name} is already a #{@locals[name][:type]}") if @locals.key?(name) && !fits?(@locals[name][:type], type)
        @locals[name] ||= { type: type, addr: local_addr(type) }
      end

      def local_addr(type)
        return @f.stack_addr(@f.slot(8)) unless @roots && type == "Value"

        at = root_slot
        off = @f.iconst("i64", at)
        @f.hoisted(:root_slot, at) { IR::Inst.new(:iadd, type: "i64", args: [@roots[:addr], off]) }
      end

      def ir_type(type)
        TYPES.fetch(type)
      end

      # The value and type of a statement list: those of the last
      # statement. `want` applies only to the last statement.
      def statements(node, want = nil)
        last = [nil, "Void"]
        node.body.each_with_index do |s, i|
          last = expr(s, i == node.body.size - 1 ? want : nil)
          break if @f.terminated?
        end
        last
      end

      # Returns `[value, type]`. `want` gives the type of a literal here.
      def expr(node, want = nil)
        case node
        when Prism::StatementsNode then statements(node, want)
        when Prism::ParenthesesNode then node.body ? statements(node.body, want) : [nil, "Void"]
        when Prism::IntegerNode
          # A Word is signed (A6), so on CRuby a bare literal at or above
          # 2**63 is not the word it is here.
          if node.value >= 1 << 63 && want != "Ptr"
            refuse(node, "a literal at or above 2**63 is a word only as Machine.word(literal)")
          end
          literal(node, node.value, want)
        when Prism::ConstantReadNode
          value = @unit.const_for(node.name.to_s) or refuse(node, "#{node.name} is not a constant here")
          literal(node, value, want)
        when Prism::AndNode then logical(node, :and)
        when Prism::OrNode then logical(node, :or)
        when Prism::TrueNode then [@f.iconst("i8", 1), "Bool"]
        when Prism::FalseNode then [@f.iconst("i8", 0), "Bool"]
        when Prism::NilNode then [nil, "Void"]
        when Prism::LocalVariableReadNode
          local = @locals[node.name.to_s] or refuse(node, "#{node.name} is read before it is assigned")
          [@f.fetch(ir_type(local[:type]), local[:addr]), local[:type]]
        when Prism::LocalVariableWriteNode
          value, type = expr(node.value, @locals.dig(node.name.to_s, :type))
          refuse(node, "#{node.name} is assigned nothing") if type == "Void"
          local = declare_local(node, node.name.to_s, type)
          @f.store(value, local[:addr])
          [value, type]
        when Prism::LocalVariableOperatorWriteNode
          local = @locals[node.name.to_s] or refuse(node, "#{node.name} is read before it is assigned")
          current = @f.fetch(ir_type(local[:type]), local[:addr])
          rhs, = expr(node.value, local[:type])
          value, type = binary(node, node.binary_operator, current, local[:type], rhs, local[:type])
          @f.store(value, local[:addr])
          [value, type]
        when Prism::CallNode then call(node, want)
        when Prism::IfNode
          branch(node, want, node.statements, node.subsequent.is_a?(Prism::ElseNode) ? node.subsequent.statements : node.subsequent)
        when Prism::UnlessNode then branch(node, want, node.else_clause&.statements, node.statements)
        when Prism::WhileNode then loop_while(node)
        when Prism::BreakNode
          refuse(node, "a break outside a while") if @loops.empty?
          refuse(node, "a break with a value") if node.arguments
          @f.jump(@loops.last)
          [nil, "Void"]
        when Prism::ReturnNode
          value, type = node.arguments ? expr(node.arguments.arguments.first, @d.ret) : [nil, "Void"]
          refuse(node, "a return of #{type} from a def whose sig says #{@d.ret}") unless fits?(@d.ret, type)
          ret(type == "Void" ? nil : value)
          [nil, "Void"]
        else
          refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not in the kernel dialect")
        end
      end

      # A size or an offset: an integer, a constant, or an operator over
      # those, folded at compile time.
      def immediate(node)
        @unit.fold_in(@d.file, node)
      end

      # An integer literal or a constant gets the type in `want`.
      def literal(node, n, want)
        type = want || "Word"
        refuse(node, "an integer where a #{type} is wanted") if ir_type(type).nil? || ir_type(type) == "f64"
        [@f.iconst(ir_type(type), n), type]
      end

      def call(node, want)
        args = node.arguments&.arguments || []
        if node.receiver.nil?
          target(node, node.name.to_s, args, imports: false)
        elsif @unit.libc?(node.receiver)
          import = @unit.import_for(node.name.to_s)
          refuse(node, "#{node.name} is not a Libc.import here") unless import.is_a?(Import)
          target(node, node.name.to_s, args)
        elsif @unit.machine?(node.receiver)
          intrinsic(node, args, want)
        elsif node.name == :call && node.receiver.is_a?(Prism::ConstantReadNode) && !@unit.sig_read?(node.receiver)
          refuse(node, "#{node.receiver.name} is not a `fn` signature here")
        elsif @unit.sig_read?(node.receiver)
          refuse(node, "a signature takes `call`") unless node.name == :call
          indirect(node, @unit.sig_for(node.receiver.name.to_s), args[0], args[1..])
        elsif node.name == :! && args.empty?
          value, type = condition_value(node.receiver)
          [@f.icmp("eq", value, @f.iconst(ir_type(type), 0)), "Bool"]
        elsif node.name == :-@ && args.empty?
          value, type = expr(node.receiver, want)
          return [@f.funop(:fneg, value), type] if type == "F64"

          refuse(node, "a negation of a #{type}") unless ir_type(type)
          [@f.isub(@f.iconst(ir_type(type), 0), value), type]
        elsif node.receiver.is_a?(Prism::ConstantReadNode) && (layout = @unit.struct_for(node.receiver.name.to_s))
          field(node, layout, args, want)
        elsif args.size == 1 && OPERATORS.key?(node.name)
          lhs, lt = expr(node.receiver, want)
          rhs, rt = expr(args.first, lt)
          binary(node, node.name, lhs, lt, rhs, rt)
        else
          refuse(node, "a call with a receiver that is not Machine or a struct")
        end
      end

      # `Name.size`, `Name.field(p)` and `Name.set_field(p, v)`. For a
      # field of a struct type, `Name.field(p)` returns its address.
      def field(node, layout, args, want)
        name = node.name.to_s
        return literal(node, layout.size, want) if name == "size" && args.empty?

        writer = name.start_with?("set_")
        fname = writer ? name.delete_prefix("set_") : name
        off, type = layout.fields.fetch(fname) { refuse(node, "#{layout.name} has no field #{fname}") }
        refuse(node, "#{layout.name}.#{name} takes #{writer ? "a pointer and a value" : "a pointer"}") if args.size != (writer ? 2 : 1)
        ptr, pt = expr(args[0])
        refuse(args[0], "#{layout.name}.#{name} of a #{pt}") unless %w[Ptr Word Value].include?(pt)
        if @unit.struct_for(type)
          refuse(node, "#{fname} is a #{type}; set its fields instead") if writer
          [off.zero? ? ptr : @f.iadd(ptr, @f.iconst("i64", off)), "Ptr"]
        elsif writer
          value, vt = expr(args[1], type)
          refuse(args[1], "#{layout.name}.#{fname} is a #{type}, not a #{vt}") unless ir_type(vt) == ir_type(type)
          region = cell?(layout) ? :heap : :malloc
          @f.store(value, ptr, off, region: region)
          barrier(ptr, value) if type == "Value" && cell?(layout)
          [nil, "Void"]
        else
          [@f.fetch(ir_type(type), ptr, off, region: cell?(layout) ? :heap : :malloc), type]
        end
      end

      # Whether a store into a field of `layout` is a store into a cell.
      # Only a cell starts with an RBasic header, so the type of the
      # first field tells. RBasic is the header itself, and a write to its
      # `klass` is a write to the cell that contains it.
      def cell?(layout)
        layout.name == "RBasic" || layout.fields.first&.last&.last == "RBasic"
      end

      # Emits the collector's write barrier after the kernel stores a
      # Value into a cell (Part 2.1 of the collector plan). CRuby writes
      # `RB_OBJ_WRITE` by hand at each such store in C, and has a second
      # collector to find the missing ones. Here the compiler emits the
      # store, so it also emits the barrier. `zr_write_barrier` is
      # `Machine.inline`, so the barrier is the four instructions of its
      # fast path and not a call.
      def barrier(owner, value)
        callee = @unit.def_for("zr_write_barrier") or return
        return if @inlining.include?(callee.name) || immediate?(value)

        inline(callee, [owner, value])
      end

      # Whether the compiler knows that `value` is an immediate, so the
      # test in the barrier fails. The kernel stores QNIL into a Value
      # field more frequently than any other value.
      def immediate?(value)
        word = @f.iconst_of(value)
        !word.nil? && @unit.immediate?(word)
      end

      # `a && b` and `a || b` as a Bool value. The right side runs only
      # when the left side does not decide the result. As the test of an
      # `if` or a `while`, `jump_if` lowers it, and it makes no value.
      #
      # A right side that is `plain?` always runs, and the two bits join
      # with no branch. It cannot change memory or fault, so an extra read
      # is not visible. This is for `zr_special_p`: it is three such tests,
      # and the collector calls it for each reference. As a diamond of
      # blocks, each test cost a compare, two sets, three widenings and
      # a branch.
      def logical(node, op)
        bit = truth(*condition_value(node.left))
        if plain?(node.right)
          other = truth(*condition_value(node.right))
          return [@f.binop(op == :and ? :band : :bor, bit, other), "Bool"]
        end

        rest = @f.label
        skip = @f.label
        merge, params = @f.block(["i8"])
        op == :and ? @f.brif(bit, rest, skip) : @f.brif(bit, skip, rest)
        @f.switch(skip)
        @f.jump(merge, [bit])
        @f.switch(rest)
        @f.jump(merge, [truth(*condition_value(node.right))])
        @f.switch(merge)
        [params.first, "Bool"]
      end

      # `value` as a Bool. A Bool is already 0 or 1. Any other integer is
      # true when it is not zero.
      def truth(value, type)
        type == "Bool" ? value : @f.icmp("ne", value, @f.iconst(ir_type(type), 0))
      end

      # Operators that lower to one instruction with no effect, and that
      # cannot fault for any operands. Division is not in this list.
      PLAIN_OPERATORS = %i[+ - * & | ^ << >> < <= > >= == != !].freeze
      PLAIN_CASTS = %i[i32 i8 word sword ptr value u8 u32].freeze

      # The operators whose result wraps at the width of the type, by
      # name. A plain `+ - * <<` must not overflow, so that it means the
      # same on CRuby (A6); a sum that must wrap names it.
      WRAPS = { add_wrap: :+, sub_wrap: :-, mul_wrap: :*, shl_wrap: :<< }.freeze

      # Whether `node` reads only literals, constants and locals, through
      # plain operators and casts. Such an expression makes only its value.
      # A local is in the frame, so a read of it is safe on any path. A
      # load through a pointer is not safe.
      def plain?(node)
        # A checked operator branches to its check, so it is not plain.
        return false if @unit.checked?

        case node
        when Prism::IntegerNode, Prism::TrueNode, Prism::FalseNode, Prism::ConstantReadNode then true
        when Prism::LocalVariableReadNode then @locals.key?(node.name.to_s)
        when Prism::ParenthesesNode then node.body.is_a?(Prism::StatementsNode) && node.body.body.one? && plain?(node.body.body[0])
        when Prism::AndNode, Prism::OrNode then plain?(node.left) && plain?(node.right)
        when Prism::CallNode
          args = node.arguments&.arguments || []
          return false if node.block || node.receiver.nil?
          if @unit.machine?(node.receiver)
            return (PLAIN_CASTS.include?(node.name) && args.one? && plain?(args[0])) ||
                   (WRAPS.key?(node.name) && args.size == 2 && args.all? { |a| plain?(a) })
          end

          PLAIN_OPERATORS.include?(node.name) && args.size <= 1 && plain?(node.receiver) && args.all? { |a| plain?(a) }
        else false
        end
      end

      OPERATORS = {
        :+ => "iadd", :- => "isub", :* => "imul", :& => "band", :| => "bor", :^ => "bxor", :<< => "ishl",
        :< => "lt", :<= => "le", :> => "gt", :>= => "ge", :== => "eq", :!= => "ne",
        :/ => nil, :% => nil, :>> => nil
      }.freeze

      # Word and Ptr can mix: a Ptr plus or minus a Word is a Ptr, a Ptr
      # minus a Ptr is a Word, and a comparison with a Ptr on one side is
      # unsigned. Value does not mix with other types.
      #
      # `named` is true for `Machine.add_wrap`, `Machine.sdiv` and the
      # others, which the checked build does not check for a wrap or a
      # negative operand.
      def binary(node, op, lhs, lt, rhs, rt, named: false)
        refuse(node, "#{op} on #{lt} and #{rt}") unless ir_type(lt) && (lt == rt || (PLAIN.include?(lt) && PLAIN.include?(rt)))
        return float_binary(node, op, lhs, rhs) if lt == "F64"

        ptr = lt == "Ptr" || rt == "Ptr"
        result = if ptr && op == :- && lt == rt then "Word"
                 elsif ptr then "Ptr"
                 else lt
                 end
        case op
        when :+, :-, :*, :&, :|, :^, :<<
          value = @f.binop(OPERATORS[op].to_sym, lhs, rhs)
          if @unit.checked? && !named
            if result == "Ptr"
              check_unsigned(node, op, lhs, lt, rhs, rt, value)
            elsif !ptr
              check_wrap(node, op, lhs, rhs, value, result)
            end
          end
          [value, result]
        when :/, :%, :>>
          check_operands(node, op, lhs, rhs, lt, ptr, named) if @unit.checked?
          mnemonic = { :/ => "div", :% => "rem", :>> => "shr" }[op]
          [@f.binop(:"#{ptr ? "u" : "s"}#{mnemonic}", lhs, rhs), result]
        when :==, :!=
          [@f.icmp(OPERATORS[op], lhs, rhs), "Bool"]
        when :<, :<=, :>, :>=
          cond = (ptr ? "u" : "s") + OPERATORS[op]
          [@f.icmp(cond, lhs, rhs), "Bool"]
        else
          refuse(node, "#{op} is not in the kernel dialect")
        end
      end

      # The checked build (`ZR_KERNEL_CHECKED`) finds each operator whose
      # meaning in the lowering differs from its meaning in Ruby. A plain
      # `+ - * <<` on a signed type (Word, I32, I8, Value) must not wrap,
      # `/ %` must not see a negative operand or a zero divisor, and `>>`
      # must shift by less than the width. A failed check prints the
      # kernel file and line and aborts (`zr_bug`). A Ptr is unsigned, so
      # only a shift of one is checked.
      CHECKED = %w[Word I32 I8 Value].freeze

      def check_wrap(node, op, lhs, rhs, value, type)
        return unless CHECKED.include?(type)

        w = ir_type(type)
        zero = @f.iconst(w, 0)
        case op
        when :+
          trap_if(node, @f.icmp("slt", @f.band(@f.binop(:bxor, lhs, value), @f.binop(:bxor, rhs, value)), zero), "+ wraps")
        when :-
          trap_if(node, @f.icmp("slt", @f.band(@f.binop(:bxor, lhs, rhs), @f.binop(:bxor, lhs, value)), zero), "- wraps")
        when :*
          # A product wraps when a nonzero factor does not divide it back,
          # or when it is the lowest value times -1.
          divide = @f.label
          done = @f.label
          @f.brif(@f.icmp("ne", lhs, zero), divide, done)
          @f.switch(divide)
          lowest = @f.iconst(w, -(1 << (bits(w) - 1)))
          back = @f.icmp("ne", @f.binop(:sdiv, value, lhs), rhs)
          negated = @f.band(@f.icmp("eq", lhs, @f.iconst(w, -1)), @f.icmp("eq", rhs, lowest))
          trap_if(node, @f.bor(back, negated), "* wraps")
          @f.jump(done)
          @f.switch(done)
        when :<<
          width = @f.iconst(w, bits(w))
          out = @f.icmp("uge", rhs, width)
          lost = @f.icmp("ne", @f.binop(:sshr, value, @f.band(rhs, @f.iconst(w, bits(w) - 1))), lhs)
          trap_if(node, @f.bor(out, lost), "<< wraps")
        end
      end

      # A Ptr is in [0, 2**64) (A6). A sum, a difference, a product or a
      # shift whose result is a Ptr must stay in that range. A Word added
      # to a Ptr is signed, so its sign says which way the Ptr may move.
      def check_unsigned(node, op, lhs, lt, rhs, rt, value)
        zero = @f.iconst("i64", 0)
        case op
        when :+, :-
          return if op == :- && lt != "Ptr" # a Word minus a Ptr is not an address

          ptr, word = lt == "Ptr" ? [lhs, rhs] : [rhs, lhs]
          up = @f.icmp("ult", value, ptr)
          down = @f.icmp("ugt", value, ptr)
          up, down = down, up if op == :-
          if lt == rt
            bad = up
          else
            forward = @f.icmp("sge", word, zero)
            bad = @f.bor(@f.band(forward, up), @f.band(@f.binop(:bxor, forward, @f.iconst("i8", 1)), down))
          end
          trap_if(node, bad, "#{op} leaves the range of a Ptr")
        when :*
          divide = @f.label
          done = @f.label
          @f.brif(@f.icmp("ne", lhs, zero), divide, done)
          @f.switch(divide)
          trap_if(node, @f.icmp("ne", @f.binop(:udiv, value, lhs), rhs), "* leaves the range of a Ptr")
          @f.jump(done)
          @f.switch(done)
        when :<<
          out = @f.icmp("uge", rhs, @f.iconst("i64", 64))
          lost = @f.icmp("ne", @f.binop(:ushr, value, @f.band(rhs, @f.iconst("i64", 63))), lhs)
          trap_if(node, @f.bor(out, lost), "<< leaves the range of a Ptr")
        end
      end

      def check_operands(node, op, lhs, rhs, type, ptr, named)
        w = ir_type(type)
        zero = @f.iconst(w, 0)
        if op == :>>
          trap_if(node, @f.icmp("uge", rhs, @f.iconst(w, bits(w))), ">> by the width or more")
          return
        end

        bad = @f.icmp("eq", rhs, zero)
        bad = @f.bor(bad, @f.bor(@f.icmp("slt", lhs, zero), @f.icmp("slt", rhs, zero))) unless ptr || named
        trap_if(node, bad, "#{op} of a negative number or by zero")
      end

      def bits(w) = { "i8" => 8, "i32" => 32, "i64" => 64 }.fetch(w)

      # Calls `zr_bug` with "file:line: what" when `bad` is true. A unit
      # without zr_bug (a test of the lowering) gets no check.
      def trap_if(node, bad, what)
        bug = @unit.def_for("zr_bug") or return
        fail = @f.label
        ok = @f.label
        @f.brif(bad, fail, ok)
        @f.switch(fail)
        text = "#{Paths.shown(@d.file)}:#{node.location.start_line}: #{what} (ZR_KERNEL_CHECKED)\n"
        fn = @f.callee(bug.name, %w[i64 i64], nil, colocated: true)
        @f.call(fn, [@f.symbol_value(@f.symbol(@unit.bytes(text))), @f.iconst("i64", text.bytesize)])
        @f.jump(ok)
        @f.switch(ok)
      end

      FLOAT_OPS = { :+ => :fadd, :- => :fsub, :* => :fmul, :/ => :fdiv }.freeze
      FLOAT_CONDS = { :== => "eq", :!= => "ne", :< => "lt", :<= => "le", :> => "gt", :>= => "ge" }.freeze

      # F64 arithmetic and comparison. A comparison with NaN on one side
      # is false, except `!=`.
      def float_binary(node, op, lhs, rhs)
        return [@f.fbinop(FLOAT_OPS[op], lhs, rhs), "F64"] if FLOAT_OPS.key?(op)
        return [@f.fcmp(FLOAT_CONDS[op], lhs, rhs), "Bool"] if FLOAT_CONDS.key?(op)

        refuse(node, "#{op} on an F64")
      end

      PLAIN = %w[Word Ptr].freeze

      def fits?(want, got)
        want == got || (PLAIN.include?(want) && PLAIN.include?(got))
      end

      # A call to an import (`Libc.name`) or to a def of this unit. A bare
      # call goes only to a def or a raw function.
      def target(node, name, args, imports: true)
        callee = @unit.def_for(name) || @unit.import_for(name)
        callee = nil if !imports && callee.is_a?(Import)
        callee or refuse(node, imports ? "#{name} is not an import or a machine def here" : "#{name} is not a def here; an import is `Libc.#{name}`")
        refuse(node, "#{name} takes #{callee.params.size} arguments, not #{args.size}") if args.size != callee.params.size
        types = callee.is_a?(Def) ? callee.params.map(&:last) : callee.params
        values = args.zip(types).map do |arg, type|
          value, got = expr(arg, type)
          refuse(arg, "#{name} wants a #{type} here, not a #{got}") unless fits?(type, got)
          rooted(arg, value, got)
        end
        return inline(callee, values) if @unit.inline?(callee) && !@inlining.include?(callee.name)

        from = callee.from if callee.is_a?(Import)
        fn = @f.callee(name, types.map { |t| ir_type(t) }, ir_type(callee.ret), colocated: !callee.is_a?(Import), from: from)
        if callee.ret == "Void"
          @f.call(fn, values)
          [nil, "Void"]
        else
          [@f.call_val(fn, values), callee.ret]
        end
      end

      # Lowers the body of `d` in place of the call, with the argument
      # `values`. Its parameters and locals are in a scope of their own,
      # as in a call. A refusal in the body gives the file of the callee.
      #
      # The body cannot collect, so nothing in it goes in the root frame.
      # A Value is in a slot of its own, and `IR::Mem2Reg` can make it a
      # register.
      #
      # A `return` in the body (frequently a guard clause at the start of
      # a small def) jumps with its value to a block after the body. The
      # last value of the body also jumps there. The parameter of that
      # block is the result of the call.
      def inline(d, values)
        outer = [@locals, @d, @roots, @exit]
        @locals = {}
        @d = d
        @roots = nil
        @exit = { type: d.ret }
        @inlining << d.name
        d.params.each_with_index do |(name, type), i|
          @f.store(values[i], declare_local(d.node, name, type)[:addr])
        end
        value, type = d.node.body ? statements(d.node.body, d.ret) : [nil, "Void"]
        unless @f.terminated?
          refuse(d.node, "the body ends in #{type}, and the sig says #{d.ret}") unless d.ret == "Void" || fits?(d.ret, type)
          ret(d.ret == "Void" ? nil : value) if @exit[:block]
        end
        if @exit[:block]
          @f.switch(@exit[:block], open: true)
          value = @exit[:value]
        end
        d.ret == "Void" ? [nil, "Void"] : [value, d.ret]
      ensure
        @inlining.pop
        @locals, @d, @roots, @exit = outer
      end

      # A Value that a call returns must stay alive across the next calls
      # in the same argument list, so it gets a root slot of its own. A
      # struct field read or a `Machine.value` is also a call here: Ruby
      # code in a later argument can free the object it refers to.
      def rooted(node, value, type)
        return value unless @roots && type == "Value" && node.is_a?(Prism::CallNode)

        @f.store(value, @roots[:addr], root_slot)
        value
      end

      def intrinsic(node, args, want)
        case node.name
        when :id
          name = args.first
          refuse(node, "Machine.id takes a symbol") unless name.is_a?(Prism::SymbolNode) && args.size == 1
          literal(node, @unit.symbols.id(name.unescaped), want)
        when :bytesize
          s = args.first
          refuse(node, "Machine.bytesize takes a string literal") unless s.is_a?(Prism::StringNode)
          literal(node, s.unescaped.bytesize, want)
        when :extern
          name = args.first
          refuse(node, "Machine.extern takes the symbol of a data object another unit defines") unless name.is_a?(Prism::SymbolNode)
          [@f.symbol_value(@f.symbol(name.unescaped, colocated: false)), "Ptr"]
        when :bytes
          s = args.first
          refuse(node, "Machine.bytes takes a string literal") unless s.is_a?(Prism::StringNode)
          [@f.symbol_value(@f.symbol(@unit.bytes(s.unescaped))), "Ptr"]
        when :load64, :load32, :load8
          width = { load64: "i64", load32: "i32", load8: "i8" }[node.name]
          ptr, pt = expr(args[0], "Ptr")
          refuse(node, "#{node.name} takes a Ptr and an offset") unless fits?("Ptr", pt) && args.size == 2
          type = { load64: "Word", load32: "I32", load8: "I8" }[node.name]
          [@f.fetch(width, ptr, immediate(args[1])), type]
        when :store64, :store32, :store8
          ptr, pt = expr(args[0], "Ptr")
          refuse(node, "#{node.name} takes a Ptr, an offset and a value") unless fits?("Ptr", pt) && args.size == 3
          type = { store64: "Word", store32: "I32", store8: "I8" }[node.name]
          value, vt = expr(args[2], type)
          refuse(node, "#{node.name} stores a #{type}, not a #{vt}") unless ir_type(vt) == ir_type(type)
          @f.store(value, ptr, immediate(args[1]))
          [nil, "Void"]
        when :slot
          refuse(node, "Machine.slot takes a size") unless args.size == 1
          [@f.stack_addr(@f.slot(immediate(args.first))), "Ptr"]
        when :static
          name, size = args
          refuse(node, "Machine.static takes a symbol and a size") unless name.is_a?(Prism::SymbolNode) && size
          [@f.symbol_value(@f.symbol(@unit.static(node, name.unescaped, immediate(size)))), "Ptr"]
        when :gates
          refuse(node, "Machine.gates takes nothing") unless args.empty?
          [@f.gates, "Word"]
        when :gates_set
          value, type = expr(args.first, "Word")
          refuse(node, "Machine.gates_set takes a Word") unless args.one? && ir_type(type) == "i64"
          @f.store(value, gates_addr(node), region: :gates)
          @f.gates_set(value)
          [nil, "Void"]
        when :gates_enter
          refuse(node, "Machine.gates_enter takes nothing") unless args.empty?
          @f.gates_enter(@f.fetch("i64", gates_addr(node), region: :gates))
          [nil, "Void"]
        when :i32, :i8, :word, :sword, :ptr, :value
          # `Machine.word(0x8080808080808080)`: the bits of a literal
          # that does not fit a signed Word.
          return literal(args.first, args.first.value, "Word") if node.name == :word && args.first.is_a?(Prism::IntegerNode)

          value, type = expr(args.first)
          convert(node, node.name, value, type)
        when :u8, :u32
          value, type = expr(args.first)
          narrow = node.name == :u8 ? "i8" : "i32"
          refuse(node, "Machine.#{node.name} of a #{type}") unless args.one? && ir_type(type) == narrow
          convert(node, :word, value, type)
        when *WRAPS.keys
          refuse(node, "Machine.#{node.name} takes two operands") unless args.size == 2
          lhs, lt = expr(args[0], want)
          rhs, rt = expr(args[1], lt)
          refuse(node, "Machine.#{node.name} of an F64") if lt == "F64" || rt == "F64"
          binary(node, WRAPS.fetch(node.name), lhs, lt, rhs, rt, named: true)
        when :sdiv, :srem
          refuse(node, "Machine.#{node.name} takes two operands") unless args.size == 2
          lhs, lt = expr(args[0], want)
          rhs, rt = expr(args[1], lt)
          refuse(node, "Machine.#{node.name} of a #{lt} and a #{rt}") unless %w[I8 I32 Word].include?(lt) && lt == rt
          binary(node, node.name == :sdiv ? :/ : :%, lhs, lt, rhs, rt, named: true)
        when :f64, :bits, :to_f64, :to_int
          value, type = expr(args.first)
          float_convert(node, node.name, value, type)
        when :ctz, :clz, :popcnt, :bswap
          value, type = expr(args.first)
          refuse(node, "Machine.#{node.name} of a #{type}") unless %w[i32 i64].include?(ir_type(type)) && args.one?
          [@f.bitop(node.name, value), type]
        when :sqrt, :floor, :ceil, :trunc, :nearest, :fabs
          value, type = expr(args.first)
          refuse(node, "Machine.#{node.name} of a #{type}") unless type == "F64"
          [@f.funop(node.name, value), "F64"]
        when :addr
          name = args.first
          refuse(node, "Machine.addr takes the symbol of a machine def") unless name.is_a?(Prism::SymbolNode)
          d = @unit.def_for(name.unescaped) or refuse(node, "#{name.unescaped} is not a machine def here")
          fn = @f.callee(d.name, d.params.map { |_, t| ir_type(t) }, ir_type(d.ret), colocated: true)
          [@f.func_addr(fn), "Ptr"]
        else
          refuse(node, "Machine.#{node.name} is not an intrinsic")
        end
      end

      # A call through the pointer `at` with the signature `s`:
      # `Name.call(at, ...)`.
      def indirect(node, s, at, rest)
        ptr, pt = expr(at || refuse(node, "#{s.name}.call takes a pointer first"), "Ptr")
        refuse(at, "#{s.name}.call through a #{pt}") unless fits?("Ptr", pt)
        refuse(node, "#{s.name} takes #{s.params.size} arguments, not #{rest.size}") if rest.size != s.params.size
        values = rest.zip(s.params).map do |arg, type|
          value, got = expr(arg, type)
          refuse(arg, "#{s.name} wants a #{type} here, not a #{got}") unless fits?(type, got)
          rooted(arg, value, got)
        end
        sig = @f.sig(s.params.map { |t| ir_type(t) }, ir_type(s.ret))
        return [@f.call_indirect(sig, ptr, values), "Void"] if s.ret == "Void"

        [@f.call_indirect_val(sig, ptr, values), s.ret]
      end

      # The static of the gate word. `Machine.gates` reads the word from
      # its register. `Machine.gates_set(word)` stores the word and sets
      # the register. `Machine.gates_enter` is first in a def that foreign
      # code calls; it loads the register from the static, and the def
      # restores the register before it returns.
      def gates_addr(node)
        @f.symbol_value(@f.symbol(@unit.static(node, "gates", 8)))
      end

      # A change of width or of type: `Machine.i32(x)` narrows, `word`
      # zero-extends, `sword` sign-extends. `ptr`, `value` and `word`
      # between 64-bit types change only the type, not the bits.
      def convert(node, to, value, type)
        target = { i32: "I32", i8: "I8", word: "Word", sword: "Word", ptr: "Ptr", value: "Value" }[to]
        from, into = ir_type(type), ir_type(target)
        refuse(node, "Machine.#{to} of a #{type}") if from.nil? || from == "f64"
        return [value, target] if from == into
        return [@f.ireduce(into, value), target] if from == "i64" || (from == "i32" && into == "i8")

        [to == :sword ? @f.sextend(into, value) : @f.uextend(into, value), target]
      end

      # `Machine.f64(word)` and `Machine.bits(f)` read the same 64 bits
      # as the other type. `to_f64` and `to_int` convert the value;
      # `to_int` saturates.
      def float_convert(node, to, value, type)
        case to
        when :f64
          refuse(node, "Machine.f64 of a #{type}") unless %w[Word Ptr Value].include?(type)
          [@f.bitcast("f64", value), "F64"]
        when :bits
          refuse(node, "Machine.bits of a #{type}") unless type == "F64"
          [@f.bitcast("i64", value), "Word"]
        when :to_f64
          refuse(node, "Machine.to_f64 of a #{type}") unless %w[Word Ptr Value].include?(type)
          [@f.fcvt_from_sint(value), "F64"]
        when :to_int
          refuse(node, "Machine.to_int of a #{type}") unless type == "F64"
          [@f.fcvt_to_sint_sat(value), "Word"]
        end
      end

      # Lowers the test `node` as a branch: to `yes` when it is true, to
      # `no` when it is false. An `&&` or `||` branches on its left side
      # and tests its right side only when the left side does not decide.
      # A `!` swaps the targets. Other nodes are tested as values. Thus a
      # test makes no bit to test (no set, no widening, no join of a byte),
      # and each compare feeds its branch directly.
      def jump_if(node, yes, no)
        case node
        when Prism::AndNode, Prism::OrNode
          rest = @f.label
          node.is_a?(Prism::AndNode) ? jump_if(node.left, rest, no) : jump_if(node.left, yes, rest)
          @f.switch(rest)
          jump_if(node.right, yes, no)
        when Prism::ParenthesesNode
          body = node.body
          return jump_if(body.body[0], yes, no) if body.is_a?(Prism::StatementsNode) && body.body.one?

          @f.brif(condition_value(node).first, yes, no)
        when Prism::CallNode
          return jump_if(node.receiver, no, yes) if node.name == :! && node.arguments.nil? && node.receiver

          @f.brif(condition_value(node).first, yes, no)
        else
          @f.brif(condition_value(node).first, yes, no)
        end
      end

      # `[value, type]` of an expression that a branch can test: any integer.
      def condition_value(node)
        value, type = expr(node)
        refuse(node, "a condition that is a #{type}") unless %w[Bool I8 I32 Word Ptr Value].include?(type)
        [value, type]
      end

      # `if` as a value when both arms have the same type, else Void. The
      # arms lower before the shape of the merge block is known, so their
      # jumps are written last. `then_stmts` is the then arm. `else_part`
      # is the statements of the else arm, an elsif, or nil.
      def branch(node, want, then_stmts, else_part)
        then_b = @f.label
        else_b = @f.label
        jump_if(node.predicate, then_b, else_b)
        @f.switch(then_b)
        tv, tt = then_stmts ? statements(then_stmts, want) : [nil, "Void"]
        then_open = !@f.terminated?
        then_end = @f.current.name
        @f.switch(else_b, open: true)
        ev, et = else_part ? expr(else_part, want) : [nil, "Void"]
        else_open = !@f.terminated?
        else_end = @f.current.name
        return [nil, "Void"] if !then_open && !else_open

        joined = then_open && else_open && tt == et && tt != "Void" ? tt : "Void"
        merge, params = joined == "Void" ? @f.block : @f.block([ir_type(joined)])
        carry = joined == "Void" ? [] : nil
        @f.finish(then_end, IR::Inst.new(:jump, targets: [[merge, carry || [tv]]])) if then_open
        @f.finish(else_end, IR::Inst.new(:jump, targets: [[merge, carry || [ev]]])) if else_open
        @f.switch(merge, open: true)
        [joined == "Void" ? nil : params.first, joined]
      end

      def loop_while(node)
        head = @f.label
        body = @f.label
        done = @f.label
        @f.jump(head)
        @f.switch(head)
        jump_if(node.predicate, body, done)
        @f.switch(body)
        @loops.push(done)
        statements(node.statements) if node.statements
        @loops.pop
        @f.jump(head) unless @f.terminated?
        @f.switch(done)
        [nil, "Void"]
      end
    end
  end
end
