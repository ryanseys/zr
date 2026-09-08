# frozen_string_literal: true

require_relative "../hir"
require_relative "../ir"
require_relative "../obj/model"

module Ze0
  module Zr
    # HIR to IR against the `zr` runtime. The toplevel is one function,
    # `zr_toplevel`, with a frame record in its frame: the record holds
    # every Value the function keeps alive across a call, so the collector
    # sees them. A send stores its receiver, then each argument, into the
    # record before the next is evaluated, and calls `zr_send` with a
    # pointer at those slots.
    class Lower
      class Refused < StandardError; end

      def initialize(program, unit, symbols)
        @program = program
        @unit = unit
        @symbols = symbols
        @frame = unit.struct_for("Frame") or raise ArgumentError, "the kernel declares no Frame"
        @task = unit.struct_for("Task")
        @data = []
      end

      # `[functions, data]`.
      def run
        [[toplevel], @data]
      end

      private

      def const(name)
        @unit.const_for(name) or raise ArgumentError, "the kernel declares no #{name}"
      end

      def offset(layout, field)
        layout.fields.fetch(field).first
      end

      def toplevel
        @f = IR::Function.new("zr_toplevel", [], "i64")
        @nvalues = values_needed(@program.body, 0)
        @sp = 0
        @record = @f.slot(@frame.size + (8 * @nvalues))
        @rec = @f.stack_addr(@record)
        task = @f.symbol_value(@f.symbol("zr_static_task"))
        globals = @f.symbol_value(@f.symbol("zr_static_globals"))
        prev = @f.fetch("i64", task, offset(@task, "top"))
        @f.store(prev, @rec, offset(@frame, "prev"))
        zero = @f.iconst("i64", 0)
        %w[meta line serial].each { |name| @f.store(zero, @rec, offset(@frame, name)) }
        @self = @f.fetch("i64", globals, 8 * const("G_MAIN"))
        @f.store(@self, @rec, offset(@frame, "self"))
        @f.store(@f.iconst("i64", @nvalues), @rec, offset(@frame, "nvalues"))
        qnil = @f.iconst("i64", const("QNIL"))
        @nvalues.times { |i| @f.store(qnil, @rec, value_offset(i)) }
        @f.store(@rec, task, offset(@task, "top"))
        last = seq(@program.body)
        @f.store(prev, task, offset(@task, "top"))
        @f.ret(last || qnil)
        @f
      end

      def value_offset(i)
        @frame.size + (8 * i)
      end

      # How many record slots the sends under `node` need at once: a
      # send holds its receiver and arguments while an argument's own
      # sends run above them.
      def values_needed(node, base)
        case node
        when Hir::Seq then node.stmts.map { |s| values_needed(s, base) }.max || base
        when Hir::Send
          top = base + 1 + node.args.size
          [top, node.recv ? values_needed(node.recv, base) : base, *node.args.map { |a| values_needed(a, top) }].max
        else base
        end
      end

      def seq(node)
        last = nil
        node.stmts.each { |s| last = expr(s) }
        last
      end

      # The Value of `node`, in a register. A caller that holds it across
      # a call stores it to the record first.
      def expr(node)
        case node
        when Hir::Seq then seq(node) || @f.iconst("i64", const("QNIL"))
        when Hir::Literal then literal(node)
        when Hir::SelfRef then @self
        when Hir::Send then call(node)
        else raise Refused, "#{@program.file}:#{node.line}: #{node.class.name.split("::").last} is not lowered yet"
        end
      end

      def literal(node)
        v = node.value
        case v
        when Integer
          raise Refused, "#{@program.file}:#{node.line}: a bignum literal is not lowered yet" unless v.bit_length < 63

          @f.iconst("i64", (v << 1) | 1)
        when Symbol then @f.iconst("i64", (@symbols.id(v) << 8) | const("SYMBOL_TAG"))
        when String
          name = "zr_lit_#{@data.size}"
          @data << Obj::Data.new(name, :text_const, v.b, align: 1)
          fn = @f.callee("zr_str_new", %w[i64 i64], "i64")
          @f.call_val(fn, [@f.symbol_value(@f.symbol(name)), @f.iconst("i64", v.bytesize)])
        when nil then @f.iconst("i64", const("QNIL"))
        when true then @f.iconst("i64", const("QTRUE"))
        when false then @f.iconst("i64", const("QFALSE"))
        end
      end

      def call(node)
        base = @sp
        @sp += 1 + node.args.size
        recv = node.recv ? expr(node.recv) : @self
        @f.store(recv, @rec, value_offset(base))
        node.args.each_with_index { |a, i| @f.store(expr(a), @rec, value_offset(base + 1 + i)) }
        recv = @f.fetch("i64", @rec, value_offset(base))
        argv = @f.iadd(@rec, @f.iconst("i64", value_offset(base + 1)))
        fn = @f.callee(node.vcall ? "zr_vcall" : "zr_send", %w[i64 i64 i64 i64], "i64")
        result = @f.call_val(fn, [recv, @f.iconst("i64", @symbols.id(node.name)), @f.iconst("i64", node.args.size), argv])
        @sp = base
        result
      end
    end
  end
end
