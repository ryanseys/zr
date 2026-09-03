# frozen_string_literal: true

module Ze0
  # A form the subset does not lower. The program is refused at the node,
  # never compiled to something that answers differently from ruby.
  class Unsupported < StandardError
    def initialize(node, what = nil)
      kind = node.class.name.sub("Prism::", "").sub(/Node\z/, "")
      super("line #{node.location.start_line}: #{what || kind} is not in ze0's subset")
    end
  end

  # A value: where it sits, and who owns it.
  #
  # `at` is a stack slot (`ssN`) or a value holding an address (`vN`, a
  # caller's slot). `owned` says this code holds a reference it must move
  # or pool; a local variable's value is only ever borrowed. `immediate`
  # says the tag can never be a heap tag, so no ownership code is needed.
  Operand = Struct.new(:at, :owned, :immediate)

  # Ruby -> CLIF, one function at a time.
  #
  # The shape is the Rust emitter's outlined form: frames, lines, the
  # release pool and every dispatch are calls into the runtime; Integer
  # arithmetic and comparison take an inline fast path when both tags say
  # Int, and every other send is the runtime's cached dynamic send.
  class Lower
    INT_ARITH = {
      :+ => ["sadd_overflow", "zeo_rt_int_add_slow"],
      :- => ["ssub_overflow", "zeo_rt_int_sub_slow"],
      :* => ["smul_overflow", "zeo_rt_int_mul_slow"],
    }.freeze
    INT_COMPARE = { :< => "slt", :> => "sgt", :<= => "sle", :>= => "sge", :== => "eq" }.freeze

    def initialize(program)
      @program = program
      @defs = {}
      @scopes = []
    end

    def lower(root)
      statements = root.statements&.body || []
      declare(statements)
      @defs.each_value { |d| lower_def(d[:node]) }
      lower_toplevel(statements.reject { |s| s.is_a?(Prism::DefNode) }, root.locals)
    end

    private

    # ---- the scope being lowered ----
    #
    # A block body will lower inside the method that wrote it, so these
    # read the top of the stack rather than one set of instance variables.
    # None may be named for a `Kernel` method: a private method on `Lower`
    # overrides one for every instance of it.

    def scope = @scopes.last
    def f = @scopes.last.f
    def kind = @scopes.last.kind
    def locals = @scopes.last.locals
    def self_operand = @scopes.last.self_operand
    def out = @scopes.last.out
    def rodata = @scopes.last.rodata
    def syms = @scopes.last.syms
    def raise_block = @scopes.last.raise_block
    def done_block = @scopes.last.done_block

    # ---- declarations ----

    # One walk over a body, collecting what lowering has to know before it
    # starts. Today that is the `def`s, so a call written above a
    # definition still resolves to it; classes and captures join them.
    def declare(statements)
      statements.each { |s| declare_def(s) if s.is_a?(Prism::DefNode) }
    end

    def declare_def(node)
      raise Unsupported.new(node, "a def with a receiver") if node.receiver
      raise Unsupported.new(node, "a def named twice") if @defs.key?(node.name)

      params = node.parameters
      if params && !(params.optionals.empty? && params.rest.nil? && params.posts.empty? &&
                     params.keywords.empty? && params.keyword_rest.nil? && params.block.nil?)
        raise Unsupported.new(node, "a parameter list beyond required positionals")
      end

      names = params ? params.requireds.map(&:name) : []
      @defs[node.name] = { params: names, node: node }
      @program.add_def(
        name: node.name,
        tramp: Names.trampoline_symbol(Names::OBJECT, node.name),
        params: names,
        line: node.location.start_line,
      )
    end

    # ---- functions ----

    # Lower `function` as a new scope, and answer it to the caller once the
    # body has left the stack.
    def in_scope(function, kind)
      @scopes.push(Scope.new(function, kind))
      yield
      @scopes.pop.f
    end

    def lower_def(node)
      names = @defs[node.name][:params]
      body_sym = Names.method_symbol(Names::OBJECT, node.name)
      function = Clif::Function.new(body_sym, ["i64"] * (names.size + 2), "i32")
      in_scope(function, :body) do
        scope.self_operand = Operand.new(f.args[0], false, false)
        scope.out = f.args.last
        prologue
        (names + (node.locals - names)).each { |n| declare_local(n) }
        status = f.val("call #{f.import("zeo_rt_stack_check")}()")
        overflow, cont = f.label, f.label
        f.ins "brif #{status}, #{overflow}, #{cont}"
        f.switch(overflow)
        f.ins "return #{f.iconst("i32", 1)}"
        f.switch(cont)
        names.each_with_index do |n, i|
          from = f.args[i + 1]
          retain_if_heap(from)
          copy(from, addr_of(locals.fetch(n).slot))
        end
        label = Names.method_label(Names::OBJECT, node.name)
        enter_frame(label, node.location.start_line, node.location.end_line)
        value = lower_statements(node.body)
        move(value, out) unless f.terminated?
        f.ins "jump #{done_block}" unless f.terminated?
        epilogue
      end
      @program.add_function(Names.method_label(Names::OBJECT, node.name), function)
      lower_trampoline(node, names.size)
    end

    # The `ValueFn` the runtime dispatches to: releases a block it was
    # handed, checks the count, and calls the body on the argument slots.
    def lower_trampoline(node, arity)
      function = Clif::Function.new(Names.trampoline_symbol(Names::OBJECT, node.name), ["i64"] * 5, "i32")
      in_scope(function, :trampoline) do
        recv, argv, argc, blk, into = f.args
        scope.rodata = f.val("symbol_value.i64 #{f.symbol("zeo_rodata")}")
        has_block = f.val("icmp ne #{blk}, #{f.iconst("i64", 0)}")
        release, check = f.label, f.label
        f.ins "brif #{has_block}, #{release}, #{check}"
        f.switch(release)
        f.ins "call #{f.import("zeo_rt_release")}(#{blk})"
        f.ins "jump #{check}"
        f.switch(check)
        n = f.iconst("i64", arity)
        fits = f.val("icmp eq #{argc}, #{n}")
        go, wrong = f.label, f.label
        f.ins "brif #{fits}, #{go}, #{wrong}"
        f.switch(wrong)
        file, file_len = rodata_ref(@program.file)
        label, label_len = rodata_ref(Names.method_label(Names::OBJECT, node.name))
        line = f.iconst("i32", node.location.start_line)
        end_line = f.iconst("i32", node.location.end_line)
        f.ins "call #{f.import("zeo_rt_frame_push")}(#{file}, #{file_len}, #{label}, #{label_len}, #{line}, #{end_line})"
        status = f.val("call #{f.import("zeo_rt_wrong_arity")}(#{argc}, #{n}, #{n})")
        f.ins "call #{f.import("zeo_rt_frame_pop")}()"
        f.ins "return #{status}"
        f.switch(go)
        args = (0...arity).map do |i|
          i.zero? ? argv : f.val("iadd.i64 #{argv}, #{f.iconst("i64", i * Capi::SLOT_BYTES)}")
        end
        body = f.callee(Names.method_symbol(Names::OBJECT, node.name), ["i64"] * (arity + 2), "i32")
        status = f.val("call #{body}(#{([recv] + args + [into]).join(", ")})")
        f.ins "return #{status}"
      end
      @program.add_function("trampoline", function)
    end

    def lower_toplevel(statements, names)
      function = Clif::Function.new(Names::TOPLEVEL, ["i64"], "i32")
      in_scope(function, :toplevel) do
        scope.out = f.args[0]
        prologue
        names.each { |n| declare_local(n) }
        enter_frame("<main>", 0, 0)
        # The top-level `self`, pooled for the frame.
        self_slot = f.slot
        f.ins "call #{f.import("zeo_rt_main_object")}(#{addr_of(self_slot)})"
        f.ins "call #{f.import("zeo_rt_pool_push")}(#{addr_of(self_slot)})"
        scope.self_operand = Operand.new(self_slot, false, false)
        statements.each do |s|
          mark = f.val("call #{f.import("zeo_rt_pool_mark")}()")
          set_line(s)
          discard(lower_expr(s))
          f.ins "call #{f.import("zeo_rt_pool_reset")}(#{mark})"
        end
        store_nil(out)
        f.ins "jump #{done_block}"
        epilogue
      end
      @program.add_function(Names::TOPLEVEL, function)
    end

    # The rodata and symbol-table bases every function reads, and the two
    # blocks every status check can land in.
    def prologue
      scope.rodata = f.val("symbol_value.i64 #{f.symbol("zeo_rodata")}")
      scope.syms = f.val("symbol_value.i64 #{f.symbol("zeo_syms")}")
      scope.raise_block = f.label
      scope.done_block = f.label
      scope.exit_block, (scope.status,) = f.block(["i32"])
    end

    def enter_frame(label, line, end_line)
      file, file_len = rodata_ref(@program.file)
      label, label_len = rodata_ref(label)
      status = f.val(
        "call #{f.import("zeo_rt_frame_enter")}(#{file}, #{file_len}, #{label}, #{label_len}, " \
        "#{f.iconst("i32", line)}, #{f.iconst("i32", end_line)})",
      )
      status_check(status)
    end

    # The shared exit: a status of 0 from `done`, 1 from `raise`, then the
    # locals released, the frame popped, and the status answered.
    def epilogue
      f.switch(done_block)
      f.ins "jump #{scope.exit_block}(#{f.iconst("i32", 0)})"
      f.switch(raise_block)
      f.ins "jump #{scope.exit_block}(#{f.iconst("i32", 1)})"
      f.switch(scope.exit_block)
      locals.each_value { |local| release_local(local) }
      f.ins "call #{f.import("zeo_rt_frame_pop")}()"
      f.ins "return #{scope.status}"
    end

    # ---- statements ----

    # The value of the last statement; every other one is discarded.
    def lower_statements(node)
      body = node.is_a?(Prism::StatementsNode) ? node.body : []
      return literal_nil if body.empty?

      value = nil
      body.each_with_index do |s, i|
        discard(value) if value
        set_line(s)
        value = lower_expr(s)
        break if f.terminated? && i < body.size - 1
      end
      value
    end

    def set_line(node)
      f.ins "call #{f.import("zeo_rt_set_line")}(#{f.iconst("i32", node.location.start_line)})"
    end

    # ---- expressions ----

    def lower_expr(node)
      case node
      when Prism::IntegerNode then literal_int(node)
      when Prism::FloatNode then literal_float(node.value)
      when Prism::StringNode then literal_string(node.unescaped)
      when Prism::NilNode then literal_nil
      when Prism::TrueNode then literal_bool(1)
      when Prism::FalseNode then literal_bool(0)
      when Prism::SymbolNode then literal_symbol(node.unescaped)
      when Prism::LocalVariableReadNode then local_read(node)
      when Prism::LocalVariableWriteNode then local_write(node)
      when Prism::CallNode then lower_call(node)
      when Prism::IfNode then lower_if(node.predicate, node.statements, node.subsequent, false)
      when Prism::UnlessNode then lower_if(node.predicate, node.statements, node.else_clause, true)
      when Prism::WhileNode then lower_while(node.predicate, node.statements, false)
      when Prism::UntilNode then lower_while(node.predicate, node.statements, true)
      when Prism::ReturnNode then lower_return(node)
      when Prism::ParenthesesNode then lower_statements(node.body)
      when Prism::StatementsNode then lower_statements(node)
      when Prism::ElseNode then lower_statements(node.statements)
      else raise Unsupported.new(node)
      end
    end

    def literal_int(node)
      value = node.value
      raise Unsupported.new(node, "an Integer literal past 64 bits") unless value.bit_length < 64

      slot = f.slot
      at = addr_of(slot)
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_INT)}, #{at}"
      f.ins "store notrap aligned #{f.iconst("i64", value)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    # A Float's bits as an i64 store: the same 8 bytes, with no float
    # literal in the text.
    def literal_float(value)
      slot = f.slot
      at = addr_of(slot)
      bits = [value].pack("G").unpack1("q>")
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_FLOAT)}, #{at}"
      f.ins "store notrap aligned #{f.iconst("i64", bits)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    def literal_string(bytes)
      slot = f.slot
      ptr, len = rodata_ref(bytes)
      f.ins "call #{f.import("zeo_rt_str_lit_ro")}(#{ptr}, #{len}, #{f.iconst("i8", Capi::UTF8)}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    def literal_nil
      slot = f.slot
      store_nil(addr_of(slot))
      Operand.new(slot, false, true)
    end

    # A Symbol is its interned id, read from the `zeo_syms` slot the
    # program's startup fills.
    def literal_symbol(name)
      slot = f.slot
      at = addr_of(slot)
      store_nil(at)
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_SYMBOL)}, #{at}"
      f.ins "store notrap aligned #{sym_id(name)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    # The id of `name` in the symbol table, as an i32.
    def sym_id(name)
      sym = @program.sym(name)
      f.val("load.i32 notrap aligned #{syms}#{sym.zero? ? "" : "+#{sym * 4}"}")
    end

    def literal_bool(bit)
      slot = f.slot
      at = addr_of(slot)
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_BOOL)}, #{at}"
      f.ins "store notrap aligned #{f.iconst("i8", bit)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    # ---- locals ----

    # A fresh local, nil until something writes it.
    def declare_local(name)
      slot = f.slot
      store_nil(addr_of(slot))
      locals[name] = Local.new(slot, false)
    end

    def local_read(node)
      Operand.new(local(node).slot, false, false)
    end

    # The old value goes after the new one is held, so `x = x` keeps it.
    def local_write(node)
      value = lower_expr(node.value)
      slot = local(node).slot
      from = addr_of(value)
      retain_if_heap(from) if !value.owned && !value.immediate
      release_if_heap(addr_of(slot))
      copy(from, addr_of(slot))
      value.owned = false
      Operand.new(slot, false, false)
    end

    def release_local(local)
      release_if_heap(addr_of(local.slot))
    end

    def local(node)
      raise Unsupported.new(node, "a local of an enclosing scope") if node.depth != 0

      locals.fetch(node.name) { raise Unsupported.new(node, "the local #{node.name} has no slot") }
    end

    # ---- calls ----

    def lower_call(node)
      raise Unsupported.new(node, "a block") if node.block
      raise Unsupported.new(node, "safe navigation") if node.call_operator_loc&.slice == "&."

      args = node.arguments&.arguments || []
      args.each do |a|
        case a
        when Prism::SplatNode, Prism::KeywordHashNode, Prism::BlockArgumentNode
          raise Unsupported.new(a, "an argument of that shape")
        end
      end
      if node.receiver.nil? && (d = @defs[node.name]) && d[:params].size == args.size
        direct_call(node, args)
      elsif node.receiver.nil? && node.name == :puts
        kernel_puts(args)
      elsif node.receiver && args.size == 1 && (INT_ARITH.key?(node.name) || INT_COMPARE.key?(node.name))
        binary_op(node, args[0])
      else
        recv = node.receiver ? lower_expr(node.receiver) : self_operand
        result = f.slot
        dynamic_send(borrow(recv), node.name, args.map { |a| lower_expr(a) }, addr_of(result))
        Operand.new(result, true, false)
      end
    end

    def direct_call(node, args)
      operands = args.map { |a| lower_expr(a) }
      result = f.slot
      body = f.callee(Names.method_symbol(Names::OBJECT, node.name), ["i64"] * (args.size + 2), "i32")
      addrs = [borrow(self_operand)] + operands.map { |o| borrow(o) } + [addr_of(result)]
      status_check(f.val("call #{body}(#{addrs.join(", ")})"))
      Operand.new(result, true, false)
    end

    def kernel_puts(args)
      argv = args_array(args.map { |a| lower_expr(a) })
      result = f.slot
      status_check(f.val("call #{f.import("zeo_rt_kernel_puts")}(#{argv}, #{f.iconst("i64", args.size)}, #{addr_of(result)})"))
      Operand.new(result, false, true)
    end

    # The cached dynamic send: `recv.name(*args)`. Not `send`: that would
    # replace `Object#send` on every Lower.
    def dynamic_send(recv, name, operands, into)
      argv = args_array(operands)
      sym_id = sym_id(name)
      site = f.val("symbol_value.i64 #{f.symbol("zeo_callsites")}")
      offset = @program.callsite * Capi::CALLSITE_BYTES
      site = f.val("iadd.i64 #{site}, #{f.iconst("i64", offset)}") unless offset.zero?
      status = f.val(
        "call #{f.import("zeo_rt_send_value_cached")}(#{site}, #{f.iconst("i32", 0)}, #{recv}, #{sym_id}, " \
        "#{argv}, #{f.iconst("i64", operands.size)}, #{f.iconst("i64", 0)}, #{into})",
      )
      status_check(status)
    end

    # The arguments of a call, contiguous: one slot of `n` values, each
    # a borrowed copy. A null pointer when there are none.
    def args_array(operands)
      return f.iconst("i64", 0) if operands.empty?

      slot = f.slot(Capi::SLOT_BYTES * operands.size)
      operands.each_with_index do |o, i|
        from = borrow(o)
        to = i.zero? ? addr_of(slot) : f.stack_addr("#{slot}+#{i * Capi::SLOT_BYTES}")
        copy(from, to)
      end
      addr_of(slot)
    end

    # `a OP b` with the Int/Int fast path inline and the send otherwise.
    def binary_op(node, arg)
      lhs = lower_expr(node.receiver)
      rhs = lower_expr(arg)
      la = borrow(lhs)
      ra = borrow(rhs)
      result = f.slot
      out_at = addr_of(result)
      int = f.iconst("i8", Capi::TAG_INT)
      both = f.val("band #{f.val("icmp eq #{tag_of(la)}, #{int}")}, #{f.val("icmp eq #{tag_of(ra)}, #{int}")}")
      fast, slow, join = f.label, f.label, f.label
      f.ins "brif #{both}, #{fast}, #{slow}"
      f.switch(fast)
      a = f.val("load.i64 notrap aligned #{la}+8")
      b = f.val("load.i64 notrap aligned #{ra}+8")
      if (arith = INT_ARITH[node.name])
        value, overflowed = f.vals("#{arith[0]} #{a}, #{b}")
        big, small = f.label, f.label
        f.ins "brif #{overflowed}, #{big}, #{small}"
        f.switch(small)
        f.ins "store notrap aligned #{int}, #{out_at}"
        f.ins "store notrap aligned #{value}, #{out_at}+8"
        f.ins "jump #{join}"
        f.switch(big)
        f.ins "call #{f.import(arith[1])}(#{la}, #{ra}, #{out_at})"
        f.ins "jump #{join}"
      else
        answer = f.val("icmp #{INT_COMPARE[node.name]} #{a}, #{b}")
        f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_BOOL)}, #{out_at}"
        f.ins "store notrap aligned #{answer}, #{out_at}+8"
        f.ins "jump #{join}"
      end
      f.switch(slow)
      dynamic_send(la, node.name, [Operand.new(rhs.at, false, rhs.immediate)], out_at)
      f.ins "jump #{join}"
      f.switch(join)
      Operand.new(result, true, false)
    end

    # ---- control flow ----

    def lower_if(predicate, statements, otherwise, negate)
      truth = truthy(lower_expr(predicate))
      yes, no, join = f.label, f.label, f.label
      result = f.slot
      f.ins "brif #{truth}, #{negate ? no : yes}, #{negate ? yes : no}"
      f.switch(yes)
      arm(lower_statements(statements), result, join)
      f.switch(no)
      arm(otherwise ? lower_expr(otherwise) : literal_nil, result, join)
      f.switch(join)
      Operand.new(result, true, false)
    end

    # One arm's value into the shared result slot, unless the arm left
    # through a `return`.
    def arm(value, result, join)
      return if f.terminated?

      move(value, addr_of(result))
      f.ins "jump #{join}"
    end

    def lower_while(predicate, statements, negate)
      mark = f.val("call #{f.import("zeo_rt_pool_mark")}()")
      head, body, done = f.label, f.label, f.label
      f.ins "jump #{head}"
      f.switch(head)
      status_check(f.val("call #{f.import("zeo_rt_check_ints")}()"))
      truth = truthy(lower_expr(predicate))
      f.ins "brif #{truth}, #{negate ? done : body}, #{negate ? body : done}"
      f.switch(body)
      (statements&.body || []).each do |s|
        set_line(s)
        discard(lower_expr(s))
        break if f.terminated?
      end
      unless f.terminated?
        f.ins "call #{f.import("zeo_rt_pool_reset")}(#{mark})"
        f.ins "jump #{head}"
      end
      f.switch(done)
      f.ins "call #{f.import("zeo_rt_pool_reset")}(#{mark})"
      literal_nil
    end

    def lower_return(node)
      raise Unsupported.new(node, "a return outside a def") unless kind == :body

      args = node.arguments&.arguments || []
      raise Unsupported.new(node, "a return of several values") if args.size > 1

      move(args.empty? ? literal_nil : lower_expr(args[0]), out)
      f.ins "jump #{done_block}"
      # Nothing runs after the jump; the slot is never written or read.
      Operand.new(f.slot, false, true)
    end

    # ---- values and ownership ----

    def addr_of(operand_or_slot)
      at = operand_or_slot.is_a?(Operand) ? operand_or_slot.at : operand_or_slot
      at.start_with?("ss") ? f.stack_addr(at) : at
    end

    def store_nil(at)
      zero = f.iconst("i64", 0)
      f.ins "store notrap aligned #{zero}, #{at}"
      f.ins "store notrap aligned #{zero}, #{at}+8"
      f.ins "store notrap aligned #{zero}, #{at}+16"
    end

    def copy(from, to)
      [0, 8, 16].each do |off|
        word = f.val("load.i64 notrap aligned #{from}#{off.zero? ? "" : "+#{off}"}")
        f.ins "store notrap aligned #{word}, #{to}#{off.zero? ? "" : "+#{off}"}"
      end
    end

    def tag_of(at)
      f.val("load.i8 notrap aligned #{at}")
    end

    # `call sym(at)` only when the value at `at` is a heap object.
    def if_heap(at, sym)
      heap = f.val("icmp uge #{tag_of(at)}, #{f.iconst("i8", Capi::TAG_HEAP)}")
      yes, no = f.label, f.label
      f.ins "brif #{heap}, #{yes}, #{no}"
      f.switch(yes)
      f.ins "call #{f.import(sym)}(#{at})"
      f.ins "jump #{no}"
      f.switch(no)
    end

    def retain_if_heap(at) = if_heap(at, "zeo_rt_retain")
    def release_if_heap(at) = if_heap(at, "zeo_rt_release")

    # An address to read `value` through without taking it: an owned
    # temporary goes to the pool first, so the frame or the statement
    # releases it.
    def borrow(value)
      at = addr_of(value)
      if value.owned && !value.immediate
        if_heap(at, "zeo_rt_pool_push")
        value.owned = false
      end
      at
    end

    # `value` into the slot at `to`, which then owns it.
    def move(value, to)
      from = addr_of(value)
      retain_if_heap(from) if !value.owned && !value.immediate
      copy(from, to)
      value.owned = false
    end

    def discard(value)
      borrow(value)
    end

    def truthy(value)
      f.val("call #{f.import("zeo_rt_truthy")}(#{borrow(value)})")
    end

    # A pointer into rodata and the byte length, for `text`.
    def rodata_ref(text)
      off = @program.intern(text)
      ptr = off.zero? ? rodata : f.val("iadd.i64 #{rodata}, #{f.iconst("i64", off)}")
      [ptr, f.iconst("i64", text.bytesize)]
    end

    def status_check(status)
      cont = f.label
      f.ins "brif #{status}, #{raise_block}, #{cont}"
      f.switch(cont)
    end
  end
end
