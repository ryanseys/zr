# frozen_string_literal: true

require_relative "../ir"
require_relative "../machine/description"
require_relative "scope"
require_relative "function/expressions"
require_relative "function/definitions"
require_relative "function/sends"
require_relative "function/control"
require_relative "function/regions"
require_relative "function/params"
require_relative "function/targets"
require_relative "function/defined"
require_relative "function/tracing"

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
    # carries the current line, for backtraces. A call answering `undef`
    # means a signal is pending: the function leaves through its landing
    # block, answering `undef` itself.
    #
    # A scope that holds a block keeps its locals in an Env cell, kept in
    # the record's first slot, so the block reads and writes them there; a
    # block reaches outer locals through its Proc's env chain.
    class Function
      include Expressions
      include Definitions
      include Sends
      include Control
      include Regions
      include Params
      include Targets
      include Defined
      include Tracing

      KINDS = { main: "KIND_MAIN", top: "KIND_TOP", def: "KIND_DEF", class: "KIND_CLASS", module: "KIND_MODULE", sclass: "KIND_SCLASS", block: "KIND_BLOCK", eval: "KIND_EVAL" }.freeze
      ABI = { main: [], top: [], def: %w[i64 i64 i64 i64 i64], class: %w[i64 i64], module: %w[i64 i64], sclass: %w[i64 i64], block: %w[i64 i64 i64 i64], eval: %w[i64 i64 i64 i64] }.freeze

      attr_reader :meta, :outer, :kind

      # The Def, Block or body node this function came from.
      def def_node
        @def
      end

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
        lower.spell(locals)
        # The locals this scope reaches outside itself: each one's depth
        # from here, in the order they are first reached, and the ones it
        # writes.
        @captures = {}
        @writes = []
        @has_env = %i[eval main].include?(@kind) || Scope.holds_block?(body) || Scope.opens_locals?(body) ||
                   default_expressions.any? { |d| Scope.holds_block?(d) || Scope.opens_locals?(d) }
        @sites = 0
        @loops = []
        @regions = []
        @retries = []
      end

      def lower
        @f = IR::Function.new(@name, ABI.fetch(@kind), "i64")
        enter
        bind_params
        trace_open
        if @kind == :block
          @body_label = @f.label
          @f.jump(@body_label)
          switch(@body_label)
        end
        last = expr(@body)
        leave(last) unless @f.terminated?
        land if @landing
        # Now the body is lowered, what it reaches outside itself is
        # known, and the table its meta names can be written.
        @l.captures_table(@name, capture_rows)
        @l.functions << @f
        @f
      end

      # The record slot of the local `node` names, `node.depth` scopes up.
      def slot_at(node)
        fn = self
        node.depth.times { fn = fn.outer }
        fn.slot_index(node)
      end

      # The data object the meta emitted for this scope's local names.
      def locals_table = "zr_locals_#{@name}"

      def slot_index(node)
        @slot_of.fetch(node.name) { @l.refuse(node, "#{node.name} is not a local of this scope") }
      end

      private

      # The prologue: the stack check, then link the record into the
      # task's chain, fill its header, nil the slots, and make the Env
      # when a block needs one.
      # The program's toplevel names its file to the runtime for `$0`.
      def program_start
        file = @f.symbol_value(@f.symbol(@l.file_bytes))
        kernel("zr_program_start", file, imm(@l.file.bytesize))
      end

      # The file's parse-time warnings, on stderr as the file starts.
      def parse_warnings
        @l.warnings.each do |line|
          text = "#{line}\n"
          kernel("zr_write_err", @f.symbol_value(@f.symbol(@l.literal(text))), imm(text.bytesize))
        end
      end

      # A core def opens with its `Primitive.attr!` rows: `:hidden` on a
      # helper CRuby has no method for, which leaves no backtrace row, and
      # `:ruby` on a method CRuby itself writes in Ruby, which answers its
      # own parameters as CRuby's does.
      def attributes
        return [] unless @l.internal? && @kind == :def

        @attributes ||= begin
          # A def with a `rescue` or `ensure` opens its protected body.
          body = @body.is_a?(Hir::Begin) ? @body.body : @body
          stmts = body.is_a?(Hir::Seq) ? body.stmts : [body]
          stmts.take_while { |stmt| attribute_row?(stmt) }.map { |stmt| stmt.args.first.value }
        end
      end

      def attribute_row?(node)
        node.is_a?(Hir::Send) && node.name == :attr! && node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Primitive &&
          node.args.first.is_a?(Hir::Literal)
      end

      def hidden_def? = attributes.include?(:hidden)

      # The name an instance variable `name` is kept under. The runtime's
      # own, the core library's and the native halves', are hidden, named
      # without their `@` as CRuby names the fields its C keeps, so a
      # program sees none of them; a def marked `:ivars` keeps the ones
      # CRuby writes in Ruby.
      def ivar_name(name)
        return name unless @l.internal?

        fn = self
        fn = fn.outer while fn.kind == :block && fn.outer
        fn.send(:attributes).include?(:ivars) ? name : name.to_s.delete_prefix("@").to_sym
      end

      def enter
        @base = @has_env ? 1 : @locals.size
        @nvalues = @base + [Scope.staging(@body), *default_expressions.map { |e| Scope.staging(e) }].max + prologue_slots
        @sp = @base
        @record = @f.slot(@frame.size + (8 * @nvalues))
        @rec = @f.stack_addr(@record)
        @task_addr = @f.fetch("i64", static("current_task"), 0)
        stack_check
        @prev = @f.fetch("i64", @task_addr, off(@task, "top"))
        @f.store(@prev, @rec, off(@frame, "prev"))
        line = @def ? @def.line : 1
        name = @def && %i[class module].include?(@kind) ? sym_id(@def.name) : 0
        params = @def.params if %i[def block].include?(@kind)
        kind = hidden_def? ? "KIND_HIDDEN" : @l.frame_kind(@kind)
        @meta = @l.meta(@name, kind, line, name, @outer&.meta, params, @locals, @has_env, attributes.include?(:ruby),
                        captures: true)
        @f.store(@f.symbol_value(@f.symbol(@meta)), @rec, off(@frame, "meta"))
        @line = line | ((@def ? @l.node_id(@def) : 0) << 32)
        @f.store(imm(@line), @rec, off(@frame, "line"))
        serial = @f.iadd(@f.fetch("i64", @task_addr, off(@task, "serial")), imm(1))
        @f.store(serial, @task_addr, off(@task, "serial"))
        @f.store(serial, @rec, off(@frame, "serial"))
        @f.store(@kind == :def ? @f.fetch("i64", @task_addr, off(@task, "mid")) : imm(0), @rec, off(@frame, "mid"))
        @f.store(@kind == :def ? @f.fetch("i64", @task_addr, off(@task, "found")) : imm(@l.const("QNIL")), @rec, off(@frame, "defined"))
        @proc = @f.args[0] if @kind == :block
        @qnil = imm(@l.const("QNIL"))
        @self = case @kind
                when :main, :top then global("G_MAIN")
                when :block then proc_field("self")
                else @f.args[0]
                end
        @cref = case @kind
                when :main, :top then global("G_TOP_CREF")
                when :def then @f.args[3]
                when :block then proc_field("cref")
                else @f.args[1]
                end
        # An eval's block is the one the scope it runs in was given, so a
        # `yield` in the string reaches the caller's block.
        @blk = case @kind
               when :def then @f.args[4]
               when :block then proc_field("blk")
               when :eval then @f.args[3]
               else @qnil
               end
        @f.store(@self, @rec, off(@frame, "self"))
        @f.store(@cref, @rec, off(@frame, "cref"))
        @f.store(@blk, @rec, off(@frame, "blk"))
        # A refinement in use belongs to the call site, not to what the
        # site called: a ruby frame of its own starts with none.
        @f.store(imm(@l.const("QNIL")), @task_addr, off(@task, "refine"))
        @f.store(imm(@nvalues), @rec, off(@frame, "nvalues"))
        @f.store(imm(@l.unit.const_for("QNIL")), @rec, off(@frame, "svar"))
        @f.store(imm(@l.unit.const_for("QNIL")), @rec, off(@frame, "lastline"))
        program_start if @kind == :main && !@l.internal?
        parse_warnings if %i[main top eval].include?(@kind) && !@l.internal?
        (0...@nvalues).each { |i| @f.store(@qnil, @rec, value_offset(i)) }
        @f.store(@rec, @task_addr, off(@task, "top"))
        return unless @has_env

        if @kind == :eval
          @env = @f.args[2]
        else
          parent = @kind == :block ? proc_field("env") : @qnil
          @env = kernel("zr_env_new", parent, imm(@locals.size), @f.symbol_value(@f.symbol(locals_table)))
        end
        @f.store(@env, @rec, value_offset(0))
        kernel("zr_toplevel_binding", @env, @self, @cref, @f.symbol_value(@f.symbol(@meta))) if @kind == :main && !@l.internal?
      end

      # SystemStackError when the record would sit below the task's stack
      # limit; nothing is linked yet, so the answer leaves at once.
      def stack_check
        limit = @f.fetch("i64", @task_addr, off(@task, "stack_limit"))
        over = @f.label
        ok = @f.label
        @f.brif(@f.icmp("ult", @rec, limit), over, ok)
        switch(over)
        @f.ret(kernel("zr_stack_overflow"))
        switch(ok)
      end

      # The landing block: a pending signal leaves the function, unless
      # it is a `return` from a block of this method, whose value is ours.
      def land
        switch(@landing, open: true)
        # A block frame catches one too: a signal whose home is this very
        # frame belongs to it, which happens when the block is a lambda
        # and a block inside it returned.
        if %i[def main top eval block].include?(@kind) && @has_env
          take(kernel("zr_catch_return", @rec))
        end
        take(kernel("zr_catch_return_here")) if @kind == :def && @def&.evals
        leave(qundef, unwinding: true)
      end

      # The value a landing block answers when the catch it just ran
      # took the signal; otherwise the block goes on.
      def take(caught)
        done = @f.label
        none = @f.label
        @f.brif(@f.icmp("eq", caught, qundef), none, done)
        switch(done)
        leave(caught)
        switch(none)
      end

      # A parameter's default runs in the prologue, staging like the body.
      def default_expressions
        return [] unless %i[def block].include?(@kind)

        p = @def.params
        p.optional.map(&:last) + p.keywords.map(&:last).compact
      end

      # The record slots the prologue keeps for itself: one for a
      # method's keyword Hash, and one per level of a destructuring
      # parameter.
      def prologue_slots
        return 0 unless %i[def block].include?(@kind)

        p = @def.params
        nested = (p.required + p.post).grep(Hir::MultiTarget).map { |t| Scope.targets(t) }.max || 0
        (keywords?(p) ? 1 : 0) + nested
      end

      # The scope leaves with `value`, firing its closing event first
      # unless it never opened: an arity error leaves before the event.
      def leave(value, unwinding: false, opened: true, line: nil)
        value = trace_close(value, unwinding, line) if opened
        @f.store(@prev, @task_addr, off(@task, "top"))
        @f.ret(value)
      end

      # A call's answer, after the test for a pending signal: `undef`
      # takes the landing block.
      def checked(value)
        go = @f.label
        @f.brif(@f.icmp("eq", value, qundef), landing, go)
        switch(go)
        value
      end

      # Continue in `block`. The line the record carries is unknown
      # again, since more than one path may arrive.
      def switch(block, open: false)
        @f.switch(block, open: open)
        @line = nil
      end

      # The line a backtrace reports for what runs next.
      def at_line(line, node_id = 0)
        word = line | (node_id << 32)
        return if word == @line

        @line = word
        @f.store(imm(word), @rec, off(@frame, "line"))
      end

      # The same for `node`, with the id of the prism node it came from in
      # the word's high half, which node_id_for_backtrace_location reads.
      def at_node(node)
        at_line(node.line, @l.node_id(node))
      end

      # The address of the kernel's static word `name`, found once per
      # function.
      def static(name)
        @f.symbol_addr(@f.symbol("zr_static_#{name}"))
      end

      # The address of a fresh cell for one site's cache: `count` of the
      # kernel's `layout` (rt/kernel/cache.rb).
      def cache(prefix, layout, count = 1)
        @f.symbol_value(@f.symbol(@l.cache_cell(prefix, @l.layout(layout).size * count)))
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

      def read_local(i, depth, name = nil)
        capture(name, depth, write: false)
        return @f.fetch("i64", @rec, value_offset(i)) if depth.zero? && !@has_env

        kernel("zr_env_get", env_at(depth), imm(i))
      end

      def write_local(i, depth, v, name = nil)
        capture(name, depth, write: true)
        if depth.zero? && !@has_env
          @f.store(v, @rec, value_offset(i))
        else
          kernel("zr_env_set", env_at(depth), imm(i), v)
        end
        v
      end

      # A local this scope reads or writes in a scope outside itself. A
      # Ractor refuses a block that reaches one and names it, so every
      # scope between the two records it: a block reaches past the block
      # that holds it.
      def capture(name, depth, write:)
        return if name.nil? || depth.zero?

        @captures[name] ||= depth
        @writes << name if write && !@writes.include?(name)
        @outer&.__send__(:capture, name, depth - 1, write: write)
      end

      # `[name, written, rebound]` for each local this scope reaches
      # outside itself: whether it writes the local, and whether the scope
      # that owns the local binds it more than once. `Ractor.shareable_proc`
      # refuses a block for either.
      def capture_rows
        @captures.map do |name, depth|
          home = self
          depth.times { home = home.outer }
          [name, @writes.include?(name), home.bindings[name] > 1]
        end
      end

      # How many times each local of this scope is bound: once for a
      # parameter, and once for every assignment to it here or in a block
      # inside, wherever it runs and however often. That is how ruby counts
      # a local that "may be reassigned": `x = 1` in a loop is one binding,
      # `x = 1; x = 2` is two.
      def bindings
        @bindings ||= begin
          counts = Scope.assignments(@body)
          params = %i[def block].include?(@kind) ? @def.params : nil
          params&.names&.each { |name| counts[name] += 1 }
          counts
        end
      end
      protected :bindings

      # `nodes` evaluated into fresh record slots, `extra` more reserved
      # after them; the block gets the address of the first slot and its
      # index, and the slots are free again after it.
      def staged(nodes, extra = 0)
        base = reserve(nodes.size + extra)
        nodes.each_with_index { |n, i| @f.store(expr(n), @rec, value_offset(base + i)) }
        result = yield(@f.iadd(@rec, imm(value_offset(base))), base)
        release(base)
        result
      end

      # The slots from `base` up are free again, and hold nothing the
      # collector would keep alive.
      def release(base)
        (base...@sp).each { |i| @f.store(@qnil, @rec, value_offset(i)) } unless @f.terminated?
        @sp = base
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

      # In a block function: whether this Proc is a lambda.
      def lambda?
        @f.icmp("ne", proc_field("lambda"), imm(0))
      end

      # In a block function: `return`, `break` and `next` leave a lambda
      # itself with `v`; a plain block does what the block does.
      def unless_lambda(v)
        plain = @f.label
        own = @f.label
        @f.brif(lambda?, own, plain)
        switch(own)
        leave(through_ensures(v))
        switch(plain)
        yield
      end

      def off(layout, field)
        layout.fields.fetch(field).first
      end

      def global(name)
        @f.fetch("i64", static("globals"), 8 * @l.const(name))
      end

      # The class the cref names innermost: where a def or a constant lands.
      def cref_class
        kernel("zr_cref_klass", @cref)
      end

      def value_offset(i)
        @frame.size + (8 * i)
      end
    end
  end
end
