# frozen_string_literal: true

require_relative "../ir"
require_relative "../machine/lower"
require_relative "scope"
require_relative "function/expressions"
require_relative "function/definitions"
require_relative "function/sends"
require_relative "function/control"

module Ze0
  module Zr
    # One IR function for one Ruby scope: the toplevel (`kind` :main, no
    # parameters), a method (:def, the method ABI), a class or module body
    # (:class or :module, taking the class and the cref) or a block
    # (:block, taking its Proc, the arguments and a block).
    #
    # Every function keeps a frame record in its frame: its locals, and
    # the slots a send fills with its receiver and arguments while the
    # next argument is evaluated, so the collector sees every Value the
    # function holds across a call. The record names its FrameMeta and
    # carries the current line, for backtraces. A call answering `qundef`
    # means a signal is pending: the function leaves through its landing
    # block, answering `qundef` itself.
    #
    # A scope that holds a block keeps its locals in an Env cell, kept in
    # the record's first slot, so the block reads and writes them there; a
    # block reaches outer locals through its Proc's env chain.
    class Function
      include Expressions
      include Definitions
      include Sends
      include Control

      KINDS = { main: "KIND_MAIN", def: "KIND_DEF", class: "KIND_CLASS", module: "KIND_MODULE", block: "KIND_BLOCK" }.freeze
      ABI = { main: [], def: %w[i64 i64 i64 i64 i64], class: %w[i64 i64], module: %w[i64 i64], block: %w[i64 i64 i64 i64] }.freeze

      attr_reader :meta, :outer

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
        @has_env = Scope.holds_block?(body)
        @sites = 0
        @loops = []
      end

      def lower
        @f = IR::Function.new(@name, ABI.fetch(@kind), "i64")
        enter
        bind_params
        last = expr(@body)
        leave(last) unless @f.terminated?
        land if @landing
        @l.functions << @f
        @f
      end

      # The record slot of the local `node` names, `node.depth` scopes up.
      def slot_at(node)
        fn = self
        node.depth.times { fn = fn.outer }
        fn.slot_index(node)
      end

      def slot_index(node)
        @slot_of.fetch(node.name) { @l.refuse(node, "#{node.name} is not a local of this scope") }
      end

      private

      # The prologue: link the record into the task's chain, fill its
      # header, nil the slots, and make the Env when a block needs one.
      def enter
        @base = @has_env ? 1 : @locals.size
        @nvalues = @base + Scope.staging(@body)
        @sp = @base
        @record = @f.slot(@frame.size + (8 * @nvalues))
        @rec = @f.stack_addr(@record)
        @task_addr = @f.symbol_value(@f.symbol("zr_static_task"))
        @prev = @f.fetch("i64", @task_addr, off(@task, "top"))
        @f.store(@prev, @rec, off(@frame, "prev"))
        line = @def ? @def.line : 1
        name = @def && %i[class module].include?(@kind) ? sym_id(@def.name) : 0
        @meta = @l.meta(@name, KINDS.fetch(@kind), line, name, @outer&.meta)
        @f.store(@f.symbol_value(@f.symbol(@meta)), @rec, off(@frame, "meta"))
        @f.store(imm(line), @rec, off(@frame, "line"))
        serial = @f.iadd(@f.fetch("i64", @task_addr, off(@task, "serial")), imm(1))
        @f.store(serial, @task_addr, off(@task, "serial"))
        @f.store(serial, @rec, off(@frame, "serial"))
        @proc = @f.args[0] if @kind == :block
        @qnil = imm(@l.const("QNIL"))
        @self = case @kind
                when :main then global("G_MAIN")
                when :block then proc_field("self")
                else @f.args[0]
                end
        @cref = case @kind
                when :main then global("G_TOP_CREF")
                when :def then @f.args[3]
                when :block then proc_field("cref")
                else @f.args[1]
                end
        @blk = case @kind
               when :def then @f.args[4]
               when :block then proc_field("blk")
               else @qnil
               end
        @f.store(@self, @rec, off(@frame, "self"))
        @f.store(@cref, @rec, off(@frame, "cref"))
        @f.store(@blk, @rec, off(@frame, "blk"))
        @f.store(imm(@nvalues), @rec, off(@frame, "nvalues"))
        (0...@nvalues).each { |i| @f.store(@qnil, @rec, value_offset(i)) }
        @f.store(@rec, @task_addr, off(@task, "top"))
        return unless @has_env

        parent = @kind == :block ? proc_field("env") : @qnil
        @env = kernel("zr_env_new", parent, imm(@locals.size))
        @f.store(@env, @rec, value_offset(0))
      end

      # The landing block: a pending signal leaves the function, unless
      # it is a `return` from a block of this method, whose value is ours.
      def land
        @f.switch(@landing, open: true)
        if %i[def main].include?(@kind) && @has_env
          caught = kernel("zr_catch_return", @rec)
          done = @f.label
          none = @f.label
          @f.brif(@f.icmp("eq", caught, qundef), none, done)
          @f.switch(done)
          leave(caught)
          @f.switch(none)
        end
        leave(qundef)
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
          count = kernel("zr_block_args", @f.args[1], @f.args[2], imm(n), out)
          argv = @f.fetch("i64", out)
          n.times do |i|
            have = @f.label
            miss = @f.label
            merge, (v,) = @f.block(["i64"])
            @f.brif(@f.icmp("slt", imm(i), count), have, miss)
            @f.switch(have)
            @f.jump(merge, [@f.fetch("i64", argv, 8 * i)])
            @f.switch(miss)
            @f.jump(merge, [@qnil])
            @f.switch(merge)
            write_local(i, 0, v)
          end
        end
      end

      def leave(value)
        @f.store(@prev, @task_addr, off(@task, "top"))
        @f.ret(value)
      end

      # A call's answer, after the test for a pending signal: `qundef`
      # takes the landing block.
      def checked(value)
        @landing ||= @f.label
        go = @f.label
        @f.brif(@f.icmp("eq", value, qundef), @landing, go)
        @f.switch(go)
        value
      end

      # The line a backtrace reports for what runs next.
      def at_line(line)
        return if line == @line

        @line = line
        @f.store(imm(line), @rec, off(@frame, "line"))
      end

      # The Env `depth` scopes up: this scope's own, or the Proc's chain.
      def env_at(depth)
        if @has_env
          depth.zero? ? @env : kernel("zr_env_up", @env, imm(depth))
        else
          base = proc_field("env")
          depth == 1 ? base : kernel("zr_env_up", base, imm(depth - 1))
        end
      end

      def read_local(i, depth)
        return @f.fetch("i64", @rec, value_offset(i)) if depth.zero? && !@has_env

        kernel("zr_env_get", env_at(depth), imm(i))
      end

      def write_local(i, depth, v)
        if depth.zero? && !@has_env
          @f.store(v, @rec, value_offset(i))
        else
          kernel("zr_env_set", env_at(depth), imm(i), v)
        end
        v
      end

      # `nodes` evaluated into fresh record slots, `extra` more reserved
      # after them; the block gets the address of the first slot and its
      # index, and the slots are free again after it.
      def staged(nodes, extra = 0)
        base = @sp
        @sp += nodes.size + extra
        nodes.each_with_index { |n, i| @f.store(expr(n), @rec, value_offset(base + i)) }
        result = yield(@f.iadd(@rec, imm(value_offset(base))), base)
        @sp = base
        result
      end

      # A call into the kernel, typed from the def's own signature.
      def kernel(name, *args)
        d = @l.kernel_def(name)
        params = d.params.map { |_, type| Machine::TYPES.fetch(type) }
        ret = Machine::TYPES.fetch(d.ret)
        raise ArgumentError, "#{name} takes #{params.size} arguments, not #{args.size}" if params.size != args.size

        fn = @f.callee(name, params, ret)
        ret ? @f.call_val(fn, args) : @f.call(fn, args)
      end

      def imm(n)
        @f.iconst("i64", n)
      end

      def qundef
        imm(@l.const("QUNDEF"))
      end

      def sym_id(name)
        @l.symbols.id(name)
      end

      def proc_field(name)
        @f.fetch("i64", @proc, off(@proc_layout, name))
      end

      def off(layout, field)
        layout.fields.fetch(field).first
      end

      def global(name)
        @f.fetch("i64", @f.symbol_value(@f.symbol("zr_static_globals")), 8 * @l.const(name))
      end

      # The class the cref names innermost: where a def or a constant lands.
      def cref_class
        @f.fetch("i64", @cref, off(@cref_layout, "klass"))
      end

      def value_offset(i)
        @frame.size + (8 * i)
      end
    end
  end
end
