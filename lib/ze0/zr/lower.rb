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
        @next = 0
      end

      # A fresh function number: functions nest, so the count of finished
      # ones does not name them.
      def number
        @next += 1
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
      def meta(fn, kind, line, name = 0, parent = nil)
        layout = layout("FrameMeta")
        file = @file_bytes ||= literal(@program.file)
        bytes = ("\0" * layout.size).b
        bytes[layout.fields.fetch("name").first, 8] = [name].pack("Q<")
        bytes[layout.fields.fetch("file_len").first, 8] = [@program.file.bytesize].pack("Q<")
        bytes[layout.fields.fetch("kind").first, 8] = [const(kind)].pack("Q<")
        bytes[layout.fields.fetch("line").first, 8] = [line].pack("Q<")
        relocs = [Obj::Reloc.new(layout.fields.fetch("file").first, :abs64, file)]
        relocs << Obj::Reloc.new(layout.fields.fetch("parent").first, :abs64, parent) if parent
        name = "zr_meta_#{fn}"
        @data << Obj::Data.new(name, :data, bytes, relocs: relocs, align: 8)
        name
      end

      def refuse(node, message)
        raise Refused, "#{@program.file}:#{node.line}: #{message}"
      end

      # The function a def becomes, lowered now and named for the site.
      def define(node)
        name = "zr_def_#{number}_#{node.name.to_s.gsub(/[^A-Za-z0-9_]/, "")}"
        Fn.new(self, name, node.locals, node.body, node, :def).lower
        name
      end

      # The function a class or module body becomes.
      def body(node)
        name = "zr_body_#{number}_#{node.name}"
        Fn.new(self, name, node.locals, node.body, node, node.is_a?(Hir::ClassDef) ? :class : :module).lower
        name
      end

      # The function a block literal becomes; `outer` is the Fn it is
      # written in.
      def block(node, outer)
        name = "zr_blk_#{number}"
        Fn.new(self, name, node.locals, node.body, node, :block, outer: outer).lower
        name
      end

      # The operators with an inline fixnum fast path, and their gates.
      OPS = {
        :+ => "GATE_PLUS", :- => "GATE_MINUS", :* => "GATE_MUL", :/ => "GATE_DIV", :% => "GATE_MOD",
        :< => "GATE_LT", :<= => "GATE_LE", :> => "GATE_GT", :>= => "GATE_GE", :== => "GATE_EQ", :!= => "GATE_NE"
      }.freeze

      # One function: the toplevel (`kind` :main, no parameters), a method
      # (:def, the method ABI), a class or module body (:class or
      # :module, taking the class and the cref) or a block (:block,
      # taking its Proc, the arguments and a block).
      #
      # A scope that holds a block keeps its locals in an Env cell, kept
      # in the record's first slot, so the block reads and writes them
      # there; a block reaches outer locals through its Proc's env chain.
      class Fn
        KINDS = { main: "KIND_MAIN", def: "KIND_DEF", class: "KIND_CLASS", module: "KIND_MODULE", block: "KIND_BLOCK" }.freeze
        ABI = { main: [], def: %w[i64 i64 i64 i64 i64], class: %w[i64 i64], module: %w[i64 i64], block: %w[i64 i64 i64 i64] }.freeze

        attr_reader :meta, :has_env

        def initialize(lower, name, locals, body, node, kind, outer: nil)
          @l = lower
          @name = name
          @locals = locals
          @body = body
          @def = node
          @kind = kind
          @outer = outer
          @frame = lower.layout("Frame")
          @task = lower.layout("Task")
          @cref_layout = lower.layout("RCref")
          @proc_layout = lower.layout("RProc")
          @slot_of = locals.each_with_index.to_h
          @has_env = holds_block?(body)
          @sites = 0
          @loops = []
        end

        def lower
          @f = IR::Function.new(@name, ABI.fetch(@kind), "i64")
          @base = @has_env ? 1 : @locals.size
          @nvalues = @base + values_needed(@body, 0)
          @sp = @base
          @record = @f.slot(@frame.size + (8 * @nvalues))
          @rec = @f.stack_addr(@record)
          @task_addr = @f.symbol_value(@f.symbol("zr_static_task"))
          @prev = @f.fetch("i64", @task_addr, off(@task, "top"))
          @f.store(@prev, @rec, off(@frame, "prev"))
          line = @def ? @def.line : 1
          name = @def && %i[class module].include?(@kind) ? @l.symbols.id(@def.name) : 0
          @meta = @l.meta(@name, KINDS.fetch(@kind), line, name, @outer&.meta)
          @f.store(@f.symbol_value(@f.symbol(@meta)), @rec, off(@frame, "meta"))
          @f.store(@f.iconst("i64", line), @rec, off(@frame, "line"))
          serial = @f.iadd(@f.fetch("i64", @task_addr, off(@task, "serial")), @f.iconst("i64", 1))
          @f.store(serial, @task_addr, off(@task, "serial"))
          @f.store(serial, @rec, off(@frame, "serial"))
          @proc = @f.args[0] if @kind == :block
          @self = case @kind
                  when :main then @f.fetch("i64", globals, 8 * @l.const("G_MAIN"))
                  when :block then proc_field("self")
                  else @f.args[0]
                  end
          @f.store(@self, @rec, off(@frame, "self"))
          @cref = case @kind
                  when :main then @f.fetch("i64", globals, 8 * @l.const("G_TOP_CREF"))
                  when :def then @f.args[3]
                  when :block then proc_field("cref")
                  else @f.args[1]
                  end
          @f.store(@cref, @rec, off(@frame, "cref"))
          @qnil = @f.iconst("i64", @l.const("QNIL"))
          @blk = case @kind
                 when :def then @f.args[4]
                 when :block then proc_field("blk")
                 else @qnil
                 end
          @f.store(@blk, @rec, off(@frame, "blk"))
          @f.store(@f.iconst("i64", @nvalues), @rec, off(@frame, "nvalues"))
          (0...@nvalues).each { |i| @f.store(@qnil, @rec, value_offset(i)) }
          @f.store(@rec, @task_addr, off(@task, "top"))
          if @has_env
            parent = @kind == :block ? proc_field("env") : @qnil
            @env = @f.call_val(@f.callee("zr_env_new", %w[i64 i64], "i64"), [parent, @f.iconst("i64", @locals.size)])
            @f.store(@env, @rec, value_offset(0))
          end
          bind_params
          @landing = nil
          last = expr(@body)
          leave(last) unless @f.terminated?
          if @landing
            @f.switch(@landing, open: true)
            if %i[def main].include?(@kind) && @has_env
              caught = @f.call_val(@f.callee("zr_catch_return", %w[i64], "i64"), [@rec])
              done = @f.label
              none = @f.label
              @f.brif(@f.icmp("eq", caught, @f.iconst("i64", @l.const("QUNDEF"))), none, done)
              @f.switch(done)
              leave(caught)
              @f.switch(none)
            end
            leave(@f.iconst("i64", @l.const("QUNDEF")))
          end
          @l.functions << @f
          @f
        end

        # Whether `node` holds a block literal of this scope (not one
        # inside a nested def or body, which is its own scope).
        def holds_block?(node)
          case node
          when Hir::Send then !node.block.nil? || (node.recv && holds_block?(node.recv)) || node.args.any? { |a| holds_block?(a) }
          when Hir::Def, Hir::ClassDef, Hir::ModuleDef, nil then false
          when Struct then node.to_a.any? { |v| v.is_a?(Struct) ? holds_block?(v) : v.is_a?(Array) && v.any? { |e| holds_block?(e) } }
          else false
          end
        end

        def proc_field(name)
          @f.fetch("i64", @proc, off(@proc_layout, name))
        end

        # Parameters into their locals: a method's from argv, a block's
        # through the block-argument rules.
        def bind_params
          case @kind
          when :def
            @def.params.each_with_index { |_, i| write_local(i, 0, @f.fetch("i64", @f.args[2], 8 * i)) }
          when :block
            n = @def.params.size
            return if n.zero?

            out = @f.stack_addr(@f.slot(8))
            count = @f.call_val(@f.callee("zr_block_args", %w[i64 i64 i64 i64], "i64"), [@f.args[1], @f.args[2], @f.iconst("i64", n), out])
            argv = @f.fetch("i64", out)
            n.times do |i|
              have = @f.label
              miss = @f.label
              merge, (v,) = @f.block(["i64"])
              @f.brif(@f.icmp("slt", @f.iconst("i64", i), count), have, miss)
              @f.switch(have)
              @f.jump(merge, [@f.fetch("i64", argv, 8 * i)])
              @f.switch(miss)
              @f.jump(merge, [@qnil])
              @f.switch(merge)
              write_local(i, 0, v)
            end
          end
        end

        # The Env `depth` scopes up: this scope's own, or the Proc's chain.
        def env_at(depth)
          if @has_env
            depth.zero? ? @env : @f.call_val(@f.callee("zr_env_up", %w[i64 i64], "i64"), [@env, @f.iconst("i64", depth)])
          else
            base = proc_field("env")
            depth == 1 ? base : @f.call_val(@f.callee("zr_env_up", %w[i64 i64], "i64"), [base, @f.iconst("i64", depth - 1)])
          end
        end

        def read_local(i, depth)
          return @f.fetch("i64", @rec, value_offset(i)) if depth.zero? && !@has_env

          @f.call_val(@f.callee("zr_env_get", %w[i64 i64], "i64"), [env_at(depth), @f.iconst("i64", i)])
        end

        def write_local(i, depth, v)
          if depth.zero? && !@has_env
            @f.store(v, @rec, value_offset(i))
          else
            @f.call_val(@f.callee("zr_env_set", %w[i64 i64 i64], "i64"), [env_at(depth), @f.iconst("i64", i), v])
          end
          v
        end

        # The slot of a local `depth` scopes up: the outer scopes' locals
        # are known from the Fn chain.
        def slot_at(node)
          fn = self
          node.depth.times { fn = fn.outer_fn }
          fn.slot_index(node)
        end

        def outer_fn
          @outer
        end

        def slot_index(node)
          @slot_of.fetch(node.name) { @l.refuse(node, "#{node.name} is not a local of this scope") }
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
            top = base + 1 + node.args.size + (node.block ? 1 : 0)
            [top, node.recv ? values_needed(node.recv, top) : base, *node.args.map { |a| values_needed(a, top) }].max
          when Hir::Yield
            top = base + node.args.size
            [top, *node.args.map { |a| values_needed(a, top) }].max
          when Hir::Break, Hir::Next then values_needed(node.value, base)
          when Hir::Assign, Hir::Return, Hir::Not, Hir::IvarWrite, Hir::ConstWrite then values_needed(node.value, base)
          when Hir::ClassDef then [node.scope.is_a?(Struct) ? values_needed(node.scope, base) : base, node.superclass ? values_needed(node.superclass, base) : base].max
          when Hir::ModuleDef, Hir::ConstRead then node.scope.is_a?(Struct) ? values_needed(node.scope, base) : base
          when Hir::ArrayLit
            top = base + node.elements.size
            [top, *node.elements.map { |e| values_needed(e, top) }].max
          when Hir::Interp
            top = base + node.parts.size
            [top, *node.parts.map { |e| values_needed(e, top) }].max
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
          when Hir::Local then read_local(slot_at(node), node.depth)
          when Hir::Assign then write_local(slot_at(node), node.depth, expr(node.value))
          when Hir::Yield then yield_block(node)
          when Hir::Break then jump_out(node, :break)
          when Hir::Next then jump_out(node, :next)
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
          when Hir::Interp
            base = @sp
            @sp += node.parts.size
            node.parts.each_with_index { |e, i| @f.store(expr(e), @rec, value_offset(base + i)) }
            argv = @f.iadd(@rec, @f.iconst("i64", value_offset(base)))
            @sp = base
            checked(@f.call_val(@f.callee("zr_str_interp", %w[i64 i64], "i64"), [@f.iconst("i64", node.parts.size), argv]))
          when Hir::IvarRead
            @f.call_val(@f.callee("zr_ivar_get", %w[i64 i64], "i64"), [@self, @f.iconst("i64", @l.symbols.id(node.name))])
          when Hir::IvarWrite
            v = expr(node.value)
            @f.call_val(@f.callee("zr_ivar_set", %w[i64 i64 i64], "i64"), [@self, @f.iconst("i64", @l.symbols.id(node.name)), v])
          when Hir::If then branch(node)
          when Hir::While then loop_while(node)
          when Hir::Return
            v = expr(node.value)
            if @kind == :block
              at_line(node.line)
              checked(@f.call_val(@f.callee("zr_return", %w[i64 i64], "i64"), [@proc, v]))
            else
              leave(v)
            end
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

        def yield_block(node)
          base = @sp
          @sp += node.args.size
          node.args.each_with_index { |a, i| @f.store(expr(a), @rec, value_offset(base + i)) }
          argv = @f.iadd(@rec, @f.iconst("i64", value_offset(base)))
          @sp = base
          at_line(node.line)
          checked(@f.call_val(@f.callee("zr_yield", %w[i64 i64 i64], "i64"), [@blk, @f.iconst("i64", node.args.size), argv]))
        end

        # `break`/`next`: out of the innermost loop when one encloses the
        # statement, else out of the block.
        def jump_out(node, kind)
          v = expr(node.value)
          if (loop = @loops.last)
            @f.jump(kind == :break ? loop[:done] : loop[:head])
            @f.switch(@f.label, open: true)
            return @qnil
          end
          @l.refuse(node, "#{kind} outside a block or loop is not lowered yet") unless @kind == :block
          if kind == :next
            leave(v)
          else
            at_line(node.line)
            checked(@f.call_val(@f.callee("zr_break", %w[i64 i64], "i64"), [@proc, v]))
          end
          @qnil
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
            fn = @f.callee(@l.program.frozen ? "zr_str_frozen" : "zr_str_new", %w[i64 i64], "i64")
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
                  elsif node.opt then { :[] => "zr_opt_aref", :[]= => "zr_opt_aset", :<< => "zr_opt_ltlt" }.fetch(node.name)
                  else "zr_send"
                  end
          fn = @f.callee(entry, %w[i64 i64 i64 i64], "i64")
          at_line(node.line)
          checked(@f.call_val(fn, [recv, @f.iconst("i64", @l.symbols.id(node.name)), @f.iconst("i64", node.args.size), argv]))
        end

        def call(node)
          base = @sp
          @sp += 1 + node.args.size + (node.block ? 1 : 0)
          recv, argv = stage(node, base)
          result = if node.block
                     call_with_block(node, recv, argv, base + 1 + node.args.size)
                   elsif node.args.size == 1 && OPS.key?(node.name) && !node.vcall
                     operator(node, recv, argv)
                   else
                     dispatch(node, recv, argv)
                   end
          @sp = base
          result
        end

        # A Proc for the block in the record slot `slot`, the send with it,
        # and the site's own `break` caught on the way out.
        def call_with_block(node, recv, argv, slot)
          fn = @l.block(node.block, self)
          site = (@sites += 1)
          ret_home = @kind == :block ? proc_field("ret_home") : @rec
          proc = @f.call_val(@f.callee("zr_proc_new", %w[i64 i64 i64 i64 i64 i64 i64 i64], "i64"),
                             [@f.func_addr(@f.callee(fn, ABI.fetch(:block), "i64")), @env, @self, @cref, @blk, @rec,
                              @f.iconst("i64", (site << 32) | node.block.params.size), ret_home])
          @f.store(proc, @rec, value_offset(slot))
          at_line(node.line)
          r = @f.call_val(@f.callee("zr_send_blk", %w[i64 i64 i64 i64 i64], "i64"),
                          [recv, @f.iconst("i64", @l.symbols.id(node.name)), @f.iconst("i64", node.args.size), argv, proc])
          sentinel = @f.iconst("i64", @l.const("QUNDEF"))
          fine = @f.label
          signal = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.icmp("eq", r, sentinel), signal, fine)
          @f.switch(fine)
          @f.jump(merge, [r])
          @f.switch(signal)
          caught = @f.call_val(@f.callee("zr_catch_break", %w[i64 i64], "i64"), [@rec, @f.iconst("i64", site)])
          @landing ||= @f.label
          ours = @f.label
          @f.brif(@f.icmp("eq", caught, sentinel), @landing, ours)
          @f.switch(ours)
          @f.jump(merge, [caught])
          @f.switch(merge)
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
          @loops << { head: head, done: done }
          expr(node.body) if node.body
          @loops.pop
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
