# frozen_string_literal: true

require_relative "../hir"
require_relative "../ir"
require_relative "../obj/model"

module Ze0
  module Zr
    # HIR to IR against the `zr` runtime. The toplevel is `zr_toplevel`;
    # each `def` is a function with the method ABI `(self, argc, argv)`.
    # Every function keeps a frame record in its frame: its locals, and
    # the slots a send fills with its receiver and arguments while the
    # next argument is evaluated, so the collector sees every Value the
    # function holds across a call. The record names its FrameMeta and
    # carries the current line, for backtraces. A call answering `undef`
    # means an exception is pending: the function leaves through its
    # landing block, answering `undef` itself.
    class Lower
      class Refused < StandardError; end

      def initialize(program, unit, symbols)
        @program = program
        @unit = unit
        @symbols = symbols
        @data = []
        @functions = []
      end

      attr_reader :program, :unit, :symbols, :data, :functions

      # `[functions, data]`.
      def run
        Fn.new(self, "zr_toplevel", @program.locals, @program.body, nil, :main).lower
        [@functions, @data]
      end

      def const(name)
        @unit.const_for(name) or raise ArgumentError, "the kernel declares no #{name}"
      end

      def layout(name)
        @unit.struct_for(name) or raise ArgumentError, "the kernel declares no #{name}"
      end

      # A read-only string literal, as data this unit carries.
      def literal(bytes)
        name = "zr_lit_#{@data.size}"
        @data << Obj::Data.new(name, :text_const, bytes.b, align: 1)
        name
      end

      # The FrameMeta of function `fn`: writable, since the runtime fills
      # in the owner and name at definition. A class body's name is the
      # class's, set here.
      def meta(fn, kind, line, name = 0)
        layout = layout("FrameMeta")
        file = @file_bytes ||= literal(@program.file)
        bytes = ("\0" * layout.size).b
        bytes[layout.fields.fetch("name").first, 8] = [name].pack("Q<")
        bytes[layout.fields.fetch("file_len").first, 8] = [@program.file.bytesize].pack("Q<")
        bytes[layout.fields.fetch("kind").first, 8] = [const(kind)].pack("Q<")
        bytes[layout.fields.fetch("line").first, 8] = [line].pack("Q<")
        name = "zr_meta_#{fn}"
        @data << Obj::Data.new(name, :data, bytes, relocs: [Obj::Reloc.new(layout.fields.fetch("file").first, :abs64, file)], align: 8)
        name
      end

      def refuse(node, message)
        raise Refused, "#{@program.file}:#{node.line}: #{message}"
      end

      # The function a def becomes, lowered now and named for the site.
      def define(node)
        name = "zr_def_#{@functions.size}_#{node.name.to_s.gsub(/[^A-Za-z0-9_]/, "")}"
        Fn.new(self, name, node.locals, node.body, node, :def).lower
        name
      end

      # The function a class or module body becomes.
      def body(node)
        name = "zr_body_#{@functions.size}_#{node.name}"
        Fn.new(self, name, node.locals, node.body, node, node.is_a?(Hir::ClassDef) ? :class : :module).lower
        name
      end

      # The operators with an inline fixnum fast path, and their gates.
      OPS = {
        :+ => "GATE_PLUS", :- => "GATE_MINUS", :* => "GATE_MUL", :/ => "GATE_DIV", :% => "GATE_MOD",
        :< => "GATE_LT", :<= => "GATE_LE", :> => "GATE_GT", :>= => "GATE_GE", :== => "GATE_EQ", :!= => "GATE_NE"
      }.freeze

      # One function: the toplevel (`kind` :main, no parameters), a method
      # (:def, the method ABI) or a class or module body (:class or
      # :module, taking the class and the cref).
      class Fn
        KINDS = { main: "KIND_MAIN", def: "KIND_DEF", class: "KIND_CLASS", module: "KIND_MODULE" }.freeze

        def initialize(lower, name, locals, body, node, kind)
          @l = lower
          @name = name
          @locals = locals
          @body = body
          @def = node
          @kind = kind
          @frame = lower.layout("Frame")
          @task = lower.layout("Task")
          @cref_layout = lower.layout("RCref")
          @slot_of = locals.each_with_index.to_h
        end

        def lower
          method = @kind == :def
          params_types = { main: [], def: %w[i64 i64 i64 i64], class: %w[i64 i64], module: %w[i64 i64] }.fetch(@kind)
          @f = IR::Function.new(@name, params_types, "i64")
          @nvalues = @locals.size + values_needed(@body, 0)
          @sp = @locals.size
          @record = @f.slot(@frame.size + (8 * @nvalues))
          @rec = @f.stack_addr(@record)
          @task_addr = @f.symbol_value(@f.symbol("zr_static_task"))
          @prev = @f.fetch("i64", @task_addr, off(@task, "top"))
          @f.store(@prev, @rec, off(@frame, "prev"))
          zero = @f.iconst("i64", 0)
          line = @def ? @def.line : 1
          @meta = @l.meta(@name, KINDS.fetch(@kind), line, @def && !method ? @l.symbols.id(@def.name) : 0)
          @f.store(@f.symbol_value(@f.symbol(@meta)), @rec, off(@frame, "meta"))
          @f.store(@f.iconst("i64", line), @rec, off(@frame, "line"))
          @f.store(zero, @rec, off(@frame, "serial"))
          @self = @kind == :main ? @f.fetch("i64", globals, 8 * @l.const("G_MAIN")) : @f.args[0]
          @f.store(@self, @rec, off(@frame, "self"))
          @cref = case @kind
                  when :main then @f.fetch("i64", globals, 8 * @l.const("G_TOP_CREF"))
                  when :def then @f.args[3]
                  else @f.args[1]
                  end
          @f.store(@cref, @rec, off(@frame, "cref"))
          @f.store(@f.iconst("i64", @nvalues), @rec, off(@frame, "nvalues"))
          @qnil = @f.iconst("i64", @l.const("QNIL"))
          params = method ? @def.params.size : 0
          params.times { |i| @f.store(@f.fetch("i64", @f.args[2], 8 * i), @rec, value_offset(i)) }
          (params...@nvalues).each { |i| @f.store(@qnil, @rec, value_offset(i)) }
          @f.store(@rec, @task_addr, off(@task, "top"))
          @landing = nil
          last = expr(@body)
          leave(last) unless @f.terminated?
          if @landing
            @f.switch(@landing, open: true)
            leave(@f.iconst("i64", @l.const("QUNDEF")))
          end
          @l.functions << @f
          @f
        end

        private

        def off(layout, field)
          layout.fields.fetch(field).first
        end

        def globals
          @f.symbol_value(@f.symbol("zr_static_globals"))
        end

        # The class the cref names innermost: where a def or a constant lands.
        def cref_class
          @f.fetch("i64", @cref, off(@cref_layout, "klass"))
        end

        def value_offset(i)
          @frame.size + (8 * i)
        end

        def leave(value)
          @f.store(@prev, @task_addr, off(@task, "top"))
          @f.ret(value)
        end

        # A call's answer, after the test for a pending exception: `undef`
        # takes the landing block.
        def checked(value)
          @landing ||= @f.label
          go = @f.label
          @f.brif(@f.icmp("eq", value, @f.iconst("i64", @l.const("QUNDEF"))), @landing, go)
          @f.switch(go)
          value
        end

        # The line a backtrace reports for what runs next.
        def at_line(line)
          return if line == @line

          @line = line
          @f.store(@f.iconst("i64", line), @rec, off(@frame, "line"))
        end

        # How many record slots the sends under `node` need at once, past
        # the locals: a send holds its receiver and arguments while an
        # argument's own sends run above them.
        def values_needed(node, base)
          case node
          when Hir::Seq then node.stmts.map { |s| values_needed(s, base) }.max || base
          when Hir::Send
            top = base + 1 + node.args.size
            [top, node.recv ? values_needed(node.recv, base) : base, *node.args.map { |a| values_needed(a, top) }].max
          when Hir::Assign, Hir::Return, Hir::Not, Hir::IvarWrite, Hir::ConstWrite then values_needed(node.value, base)
          when Hir::ClassDef then [node.scope.is_a?(Struct) ? values_needed(node.scope, base) : base, node.superclass ? values_needed(node.superclass, base) : base].max
          when Hir::ModuleDef, Hir::ConstRead then node.scope.is_a?(Struct) ? values_needed(node.scope, base) : base
          when Hir::ArrayLit
            top = base + node.elements.size
            [top, *node.elements.map { |e| values_needed(e, top) }].max
          when Hir::If then [values_needed(node.cond, base), *[node.yes, node.no].compact.map { |n| values_needed(n, base) }].max
          when Hir::While then [values_needed(node.cond, base), node.body ? values_needed(node.body, base) : base].max
          when Hir::And, Hir::Or then [values_needed(node.left, base), values_needed(node.right, base)].max
          else base
          end
        end

        def seq(node)
          last = nil
          node.stmts.each do |s|
            last = expr(s)
            break if @f.terminated?
          end
          last || @qnil
        end

        # The Value of `node`, in a register. A caller that holds it across
        # a call stores it to the record first.
        def expr(node)
          case node
          when Hir::Seq then seq(node)
          when Hir::Literal then literal(node)
          when Hir::SelfRef then @self
          when Hir::Send then call(node)
          when Hir::Local then @f.fetch("i64", @rec, value_offset(slot(node)))
          when Hir::Assign
            v = expr(node.value)
            @f.store(v, @rec, value_offset(slot(node)))
            v
          when Hir::Def
            fn = @l.define(node)
            addr = @f.func_addr(@f.callee(fn, %w[i64 i64 i64 i64], "i64"))
            define = @f.callee("zr_define_method", %w[i64 i64 i64 i64 i64 i64 i64], nil)
            meta = @f.symbol_value(@f.symbol("zr_meta_#{fn}"))
            @f.call(define, [cref_class, @f.iconst("i64", @l.symbols.id(node.name)), addr, @f.iconst("i64", node.params.size),
                             @f.iconst("i64", @l.const("KIND_DEF")), meta, @cref])
            symbol(node.name)
          when Hir::ClassDef, Hir::ModuleDef then class_body(node)
          when Hir::ConstRead then const_read(node)
          when Hir::ConstWrite
            scope = scope_class(node.scope)
            v = expr(node.value)
            @f.call(@f.callee("zr_const_set", %w[i64 i64 i64], nil), [scope, @f.iconst("i64", @l.symbols.id(node.name)), v])
            v
          when Hir::ArrayLit
            # Elements wait in record slots, then become one Array.
            base = @sp
            @sp += node.elements.size
            node.elements.each_with_index { |e, i| @f.store(expr(e), @rec, value_offset(base + i)) }
            argv = @f.iadd(@rec, @f.iconst("i64", value_offset(base)))
            @sp = base
            @f.call_val(@f.callee("zr_ary_of", %w[i64 i64], "i64"), [@f.iconst("i64", node.elements.size), argv])
          when Hir::IvarRead
            @f.call_val(@f.callee("zr_ivar_get", %w[i64 i64], "i64"), [@self, @f.iconst("i64", @l.symbols.id(node.name))])
          when Hir::IvarWrite
            v = expr(node.value)
            @f.call_val(@f.callee("zr_ivar_set", %w[i64 i64 i64], "i64"), [@self, @f.iconst("i64", @l.symbols.id(node.name)), v])
          when Hir::If then branch(node)
          when Hir::While then loop_while(node)
          when Hir::Return
            leave(expr(node.value))
            @qnil
          when Hir::And, Hir::Or then logical(node)
          when Hir::Not then negate(node)
          else @l.refuse(node, "#{node.class.name.split("::").last} is not lowered yet")
          end
        end

        # The class a constant path's scope names: the cref's class for a
        # bare name, Object for `::`, else the expression's value.
        def scope_class(scope)
          case scope
          when nil then cref_class
          when :top then @f.fetch("i64", globals, 8 * @l.const("G_OBJECT"))
          else expr(scope)
          end
        end

        def const_read(node)
          id = @f.iconst("i64", @l.symbols.id(node.name))
          at_line(node.line)
          if node.scope.nil?
            checked(@f.call_val(@f.callee("zr_const_get", %w[i64 i64], "i64"), [@cref, id]))
          else
            checked(@f.call_val(@f.callee("zr_const_get_at", %w[i64 i64], "i64"), [scope_class(node.scope), id]))
          end
        end

        # `class`/`module`: define or reopen under the scope, push a cref,
        # run the body function with the class as self.
        def class_body(node)
          fn = @l.body(node)
          scope = scope_class(node.scope)
          id = @f.iconst("i64", @l.symbols.id(node.name))
          at_line(node.line)
          klass = if node.is_a?(Hir::ClassDef)
                    sup = node.superclass ? expr(node.superclass) : @f.iconst("i64", @l.const("QUNDEF"))
                    checked(@f.call_val(@f.callee("zr_class_define", %w[i64 i64 i64], "i64"), [scope, id, sup]))
                  else
                    checked(@f.call_val(@f.callee("zr_module_define", %w[i64 i64], "i64"), [scope, id]))
                  end
          cref = @f.call_val(@f.callee("zr_cref_push", %w[i64 i64], "i64"), [klass, @cref])
          checked(@f.call_val(@f.callee(fn, %w[i64 i64], "i64"), [klass, cref]))
        end

        def slot(node)
          @slot_of.fetch(node.name) { @l.refuse(node, "#{node.name} is not a local of this scope") }
        end

        def symbol(name)
          @f.iconst("i64", (@l.symbols.id(name) << 8) | @l.const("SYMBOL_TAG"))
        end

        def literal(node)
          v = node.value
          case v
          when Integer
            @l.refuse(node, "a bignum literal is not lowered yet") unless v.bit_length < 63

            @f.iconst("i64", (v << 1) | 1)
          when Symbol then symbol(v)
          when String
            fn = @f.callee("zr_str_new", %w[i64 i64], "i64")
            @f.call_val(fn, [@f.symbol_value(@f.symbol(@l.literal(v))), @f.iconst("i64", v.bytesize)])
          when nil then @qnil
          when true then @f.iconst("i64", @l.const("QTRUE"))
          when false then @f.iconst("i64", @l.const("QFALSE"))
          end
        end

        # `[recv, argv]` after the receiver and arguments are in the
        # record's slots from `base`.
        def stage(node, base)
          recv = node.recv ? expr(node.recv) : @self
          @f.store(recv, @rec, value_offset(base))
          node.args.each_with_index { |a, i| @f.store(expr(a), @rec, value_offset(base + 1 + i)) }
          [@f.fetch("i64", @rec, value_offset(base)), @f.iadd(@rec, @f.iconst("i64", value_offset(base + 1)))]
        end

        def dispatch(node, recv, argv)
          entry = if node.vcall then "zr_vcall"
                  elsif node.index then node.name == :[] ? "zr_opt_aref" : "zr_opt_aset"
                  else "zr_send"
                  end
          fn = @f.callee(entry, %w[i64 i64 i64 i64], "i64")
          at_line(node.line)
          checked(@f.call_val(fn, [recv, @f.iconst("i64", @l.symbols.id(node.name)), @f.iconst("i64", node.args.size), argv]))
        end

        def call(node)
          base = @sp
          @sp += 1 + node.args.size
          recv, argv = stage(node, base)
          result = if node.args.size == 1 && OPS.key?(node.name) && !node.vcall
                     operator(node, recv, argv)
                   else
                     dispatch(node, recv, argv)
                   end
          @sp = base
          result
        end

        # The condition a Value's truthiness gives: anything but nil and false.
        def truthy(v)
          @f.icmp("ne", @f.band(v, @f.iconst("i64", -9)), @f.iconst("i64", 0))
        end

        def gate_clear(name)
          gates = @f.fetch("i64", @f.symbol_value(@f.symbol("zr_static_gates")))
          @f.icmp("eq", @f.band(gates, @f.iconst("i64", @l.const(name))), @f.iconst("i64", 0))
        end

        # An Integer operator: the fixnum fast path inline when both sides
        # are fixnums (the receiver alone for equality) and the gate is
        # clear, else the call.
        def operator(node, recv, argv)
          arg = @f.fetch("i64", argv)
          both = %i[== !=].include?(node.name) ? recv : @f.band(recv, arg)
          fix = @f.icmp("eq", @f.band(both, @f.iconst("i64", 1)), @f.iconst("i64", 1))
          ok = @f.band(fix, gate_clear(OPS.fetch(node.name)))
          fast = @f.label
          slow = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(ok, fast, slow)
          @f.switch(fast)
          value = fast_path(node.name, recv, arg, slow)
          @f.jump(merge, [value])
          @f.switch(slow)
          @f.jump(merge, [dispatch(node, recv, argv)])
          @f.switch(merge)
          result
        end

        # The tagged result of `op` on tagged fixnums `a` and `b`; a
        # result outside the fixnum range takes `slow`.
        def fast_path(op, a, b, slow)
          one = @f.iconst("i64", 1)
          case op
          when :+ then overflow_or(@f.sadd_overflow(a, @f.isub(b, one)), slow)
          when :- then @f.bor(overflow_or(@f.ssub_overflow(a, b), slow), one)
          when :* then @f.bor(overflow_or(@f.smul_overflow(@f.sshr(a, one), @f.isub(b, one)), slow), one)
          when :/, :%
            # -2^62 / -1 leaves the fixnum range: that pair takes the call.
            x = @f.sshr(a, one)
            y = @f.sshr(b, one)
            ok = @f.label
            @f.brif(@f.icmp("eq", y, @f.iconst("i64", 0)), slow, ok)
            @f.switch(ok)
            if op == :/
              ok = @f.label
              @f.brif(@f.icmp("eq", y, @f.iconst("i64", -1)), slow, ok)
              @f.switch(ok)
            end
            fn = @f.callee(op == :/ ? "zr_floor_div" : "zr_floor_mod", %w[i64 i64], "i64")
            @f.bor(@f.ishl(@f.call_val(fn, [x, y]), one), one)
          when :<, :<=, :>, :>=, :==, :!=
            cond = { :< => "slt", :<= => "sle", :> => "sgt", :>= => "sge", :== => "eq", :!= => "ne" }.fetch(op)
            @f.csel(@f.icmp(cond, a, b), @f.iconst("i64", @l.const("QTRUE")), @f.iconst("i64", @l.const("QFALSE")))
          end
        end

        def overflow_or((value, flag), slow)
          ok = @f.label
          @f.brif(flag, slow, ok)
          @f.switch(ok)
          value
        end

        def branch(node)
          cond = truthy(expr(node.cond))
          then_b = @f.label
          else_b = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(cond, then_b, else_b)
          @f.switch(then_b)
          v = node.yes ? expr(node.yes) : @qnil
          @f.jump(merge, [v]) unless @f.terminated?
          @f.switch(else_b, open: !@f.terminated?)
          v = node.no ? expr(node.no) : @qnil
          @f.jump(merge, [v]) unless @f.terminated?
          @f.switch(merge)
          result
        end

        def loop_while(node)
          head = @f.label
          body = @f.label
          done = @f.label
          @f.jump(head)
          @f.switch(head)
          @f.brif(truthy(expr(node.cond)), body, done)
          @f.switch(body)
          expr(node.body) if node.body
          @f.jump(head) unless @f.terminated?
          @f.switch(done)
          @qnil
        end

        # `a && b` answers `a` when it is falsy, else `b`; `||` the reverse.
        def logical(node)
          left = expr(node.left)
          rest = @f.label
          skip = @f.label
          merge, (result,) = @f.block(["i64"])
          cond = truthy(left)
          node.is_a?(Hir::And) ? @f.brif(cond, rest, skip) : @f.brif(cond, skip, rest)
          @f.switch(skip)
          @f.jump(merge, [left])
          @f.switch(rest)
          right = expr(node.right)
          @f.jump(merge, [right]) unless @f.terminated?
          @f.switch(merge)
          result
        end

        # `!v` inline while BasicObject#! is the runtime's own.
        def negate(node)
          base = @sp
          @sp += 1
          v = expr(node.value)
          @f.store(v, @rec, value_offset(base))
          fast = @f.label
          slow = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(gate_clear("GATE_NOT"), fast, slow)
          @f.switch(fast)
          @f.jump(merge, [@f.csel(truthy(v), @f.iconst("i64", @l.const("QFALSE")), @f.iconst("i64", @l.const("QTRUE")))])
          @f.switch(slow)
          fn = @f.callee("zr_send", %w[i64 i64 i64 i64], "i64")
          argv = @f.iadd(@rec, @f.iconst("i64", value_offset(base + 1)))
          at_line(node.line)
          @f.jump(merge, [checked(@f.call_val(fn, [v, @f.iconst("i64", @l.symbols.id(:!)), @f.iconst("i64", 0), argv]))])
          @f.switch(merge)
          @sp = base
          result
        end
      end
    end
  end
end
