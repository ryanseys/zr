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
    end

    def lower(root)
      statements = root.statements&.body || []
      statements.grep(Prism::DefNode).each { |d| declare_def(d) }
      statements.grep(Prism::DefNode).each { |d| lower_def(d) }
      lower_toplevel(statements.reject { |s| s.is_a?(Prism::DefNode) }, root.locals)
    end

    private

    # ---- functions ----

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
        tramp: Names.trampoline_symbol(node.name),
        params: names,
        line: node.location.start_line,
      )
    end

    def lower_def(node)
      names = @defs[node.name][:params]
      body_sym = Names.method_symbol(node.name)
      @f = Clif::Function.new(body_sym, ["i64"] * (names.size + 2), "i32")
      @self = Operand.new(@f.args[0], false, false)
      @out = @f.args.last
      @locals = {}
      @kind = :body
      prologue
      (names + (node.locals - names)).each { |n| @locals[n] = zeroed_slot }
      status = @f.val("call #{@f.import("zeo_rt_stack_check")}()")
      overflow, cont = @f.block.first, @f.block.first
      @f.ins "brif #{status}, #{overflow}, #{cont}"
      @f.switch(overflow)
      @f.ins "return #{@f.iconst("i32", 1)}"
      @f.switch(cont)
      names.each_with_index do |n, i|
        from = @f.args[i + 1]
        retain_if_heap(from)
        copy(from, addr_of(@locals[n]))
      end
      enter_frame(Names.method_label(node.name), node.location.start_line, node.location.end_line)
      value = lower_statements(node.body)
      move(value, @out) unless @f.terminated?
      @f.ins "jump #{@done}" unless @f.terminated?
      epilogue
      @program.add_function("Object##{node.name}", @f)
      lower_trampoline(node, names.size)
    end

    # The `ValueFn` the runtime dispatches to: releases a block it was
    # handed, checks the count, and calls the body on the argument slots.
    def lower_trampoline(node, arity)
      f = Clif::Function.new(Names.trampoline_symbol(node.name), ["i64"] * 5, "i32")
      recv, argv, argc, blk, out = f.args
      rodata = f.val("symbol_value.i64 #{f.symbol("zeo_rodata")}")
      has_block = f.val("icmp ne #{blk}, #{f.iconst("i64", 0)}")
      release, check = f.block.first, f.block.first
      f.ins "brif #{has_block}, #{release}, #{check}"
      f.switch(release)
      f.ins "call #{f.import("zeo_rt_release")}(#{blk})"
      f.ins "jump #{check}"
      f.switch(check)
      n = f.iconst("i64", arity)
      fits = f.val("icmp eq #{argc}, #{n}")
      go, wrong = f.block.first, f.block.first
      f.ins "brif #{fits}, #{go}, #{wrong}"
      f.switch(wrong)
      file, file_len = rodata_ref(f, rodata, @program.file)
      label, label_len = rodata_ref(f, rodata, Names.method_label(node.name))
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
      body = f.callee(Names.method_symbol(node.name), ["i64"] * (arity + 2), "i32")
      status = f.val("call #{body}(#{([recv] + args + [out]).join(", ")})")
      f.ins "return #{status}"
      @program.add_function("trampoline", f)
    end

    def lower_toplevel(statements, locals)
      @f = Clif::Function.new(Names::TOPLEVEL, ["i64"], "i32")
      @out = @f.args[0]
      @locals = {}
      @kind = :toplevel
      prologue
      locals.each { |n| @locals[n] = zeroed_slot }
      enter_frame("<main>", 0, 0)
      # The top-level `self`, pooled for the frame.
      self_slot = @f.slot
      @f.ins "call #{@f.import("zeo_rt_main_object")}(#{addr_of(self_slot)})"
      @f.ins "call #{@f.import("zeo_rt_pool_push")}(#{addr_of(self_slot)})"
      @self = Operand.new(self_slot, false, false)
      statements.each do |s|
        mark = @f.val("call #{@f.import("zeo_rt_pool_mark")}()")
        set_line(s)
        discard(lower_expr(s))
        @f.ins "call #{@f.import("zeo_rt_pool_reset")}(#{mark})"
      end
      store_nil(@out)
      @f.ins "jump #{@done}"
      epilogue
      @program.add_function(Names::TOPLEVEL, @f)
    end

    # The rodata and symbol-table bases every function reads, and the two
    # blocks every status check can land in.
    def prologue
      @rodata = @f.val("symbol_value.i64 #{@f.symbol("zeo_rodata")}")
      @syms = @f.val("symbol_value.i64 #{@f.symbol("zeo_syms")}")
      @raise = @f.block.first
      @done = @f.block.first
      @exit, (@status,) = @f.block(["i32"])
    end

    def enter_frame(label, line, end_line)
      file, file_len = rodata_ref(@f, @rodata, @program.file)
      label, label_len = rodata_ref(@f, @rodata, label)
      status = @f.val(
        "call #{@f.import("zeo_rt_frame_enter")}(#{file}, #{file_len}, #{label}, #{label_len}, " \
        "#{@f.iconst("i32", line)}, #{@f.iconst("i32", end_line)})",
      )
      status_check(status)
    end

    # The shared exit: a status of 0 from `done`, 1 from `raise`, then the
    # locals released, the frame popped, and the status answered.
    def epilogue
      @f.switch(@done)
      @f.ins "jump #{@exit}(#{@f.iconst("i32", 0)})"
      @f.switch(@raise)
      @f.ins "jump #{@exit}(#{@f.iconst("i32", 1)})"
      @f.switch(@exit)
      @locals.each_value { |slot| release_if_heap(addr_of(slot)) }
      @f.ins "call #{@f.import("zeo_rt_frame_pop")}()"
      @f.ins "return #{@status}"
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
        break if @f.terminated? && i < body.size - 1
      end
      value
    end

    def set_line(node)
      @f.ins "call #{@f.import("zeo_rt_set_line")}(#{@f.iconst("i32", node.location.start_line)})"
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

      slot = @f.slot
      at = addr_of(slot)
      @f.ins "store notrap aligned #{@f.iconst("i8", Capi::TAG_INT)}, #{at}"
      @f.ins "store notrap aligned #{@f.iconst("i64", value)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    # A Float's bits as an i64 store: the same 8 bytes, with no float
    # literal in the text.
    def literal_float(value)
      slot = @f.slot
      at = addr_of(slot)
      bits = [value].pack("G").unpack1("q>")
      @f.ins "store notrap aligned #{@f.iconst("i8", Capi::TAG_FLOAT)}, #{at}"
      @f.ins "store notrap aligned #{@f.iconst("i64", bits)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    def literal_string(bytes)
      slot = @f.slot
      ptr, len = rodata_ref(@f, @rodata, bytes)
      @f.ins "call #{@f.import("zeo_rt_str_lit_ro")}(#{ptr}, #{len}, #{@f.iconst("i8", Capi::UTF8)}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    def literal_nil
      slot = @f.slot
      store_nil(addr_of(slot))
      Operand.new(slot, false, true)
    end

    # A Symbol is its interned id, read from the `zeo_syms` slot the
    # program's startup fills.
    def literal_symbol(name)
      slot = @f.slot
      at = addr_of(slot)
      store_nil(at)
      @f.ins "store notrap aligned #{@f.iconst("i8", Capi::TAG_SYMBOL)}, #{at}"
      @f.ins "store notrap aligned #{sym_id(name)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    # The id of `name` in the symbol table, as an i32.
    def sym_id(name)
      sym = @program.sym(name)
      @f.val("load.i32 notrap aligned #{@syms}#{sym.zero? ? "" : "+#{sym * 4}"}")
    end

    def literal_bool(bit)
      slot = @f.slot
      at = addr_of(slot)
      @f.ins "store notrap aligned #{@f.iconst("i8", Capi::TAG_BOOL)}, #{at}"
      @f.ins "store notrap aligned #{@f.iconst("i8", bit)}, #{at}+8"
      Operand.new(slot, false, true)
    end

    def local_read(node)
      Operand.new(local(node), false, false)
    end

    # The old value goes after the new one is held, so `x = x` keeps it.
    def local_write(node)
      value = lower_expr(node.value)
      slot = local(node)
      from = addr_of(value)
      retain_if_heap(from) if !value.owned && !value.immediate
      release_if_heap(addr_of(slot))
      copy(from, addr_of(slot))
      value.owned = false
      Operand.new(slot, false, false)
    end

    def local(node)
      raise Unsupported.new(node, "a local of an enclosing scope") if node.depth != 0

      @locals.fetch(node.name) { raise Unsupported.new(node, "the local #{node.name} has no slot") }
    end

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
        recv = node.receiver ? lower_expr(node.receiver) : @self
        out = @f.slot
        send(borrow(recv), node.name, args.map { |a| lower_expr(a) }, addr_of(out))
        Operand.new(out, true, false)
      end
    end

    def direct_call(node, args)
      operands = args.map { |a| lower_expr(a) }
      out = @f.slot
      body = @f.callee(Names.method_symbol(node.name), ["i64"] * (args.size + 2), "i32")
      addrs = [borrow(@self)] + operands.map { |o| borrow(o) } + [addr_of(out)]
      status_check(@f.val("call #{body}(#{addrs.join(", ")})"))
      Operand.new(out, true, false)
    end

    def kernel_puts(args)
      argv = args_array(args.map { |a| lower_expr(a) })
      out = @f.slot
      status_check(@f.val("call #{@f.import("zeo_rt_kernel_puts")}(#{argv}, #{@f.iconst("i64", args.size)}, #{addr_of(out)})"))
      Operand.new(out, false, true)
    end

    # The cached dynamic send: `recv.name(*args)`.
    def send(recv, name, operands, out)
      argv = args_array(operands)
      sym_id = sym_id(name)
      site = @f.val("symbol_value.i64 #{@f.symbol("zeo_callsites")}")
      offset = @program.callsite * Capi::CALLSITE_BYTES
      site = @f.val("iadd.i64 #{site}, #{@f.iconst("i64", offset)}") unless offset.zero?
      status = @f.val(
        "call #{@f.import("zeo_rt_send_value_cached")}(#{site}, #{@f.iconst("i32", 0)}, #{recv}, #{sym_id}, " \
        "#{argv}, #{@f.iconst("i64", operands.size)}, #{@f.iconst("i64", 0)}, #{out})",
      )
      status_check(status)
    end

    # The arguments of a call, contiguous: one slot of `n` values, each
    # a borrowed copy. A null pointer when there are none.
    def args_array(operands)
      return @f.iconst("i64", 0) if operands.empty?

      slot = @f.slot(Capi::SLOT_BYTES * operands.size)
      operands.each_with_index do |o, i|
        from = borrow(o)
        to = i.zero? ? addr_of(slot) : @f.val("stack_addr.i64 #{slot}+#{i * Capi::SLOT_BYTES}")
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
      out = @f.slot
      out_at = addr_of(out)
      int = @f.iconst("i8", Capi::TAG_INT)
      both = @f.val("band #{@f.val("icmp eq #{tag_of(la)}, #{int}")}, #{@f.val("icmp eq #{tag_of(ra)}, #{int}")}")
      fast, slow, join = @f.block.first, @f.block.first, @f.block.first
      @f.ins "brif #{both}, #{fast}, #{slow}"
      @f.switch(fast)
      a = @f.val("load.i64 notrap aligned #{la}+8")
      b = @f.val("load.i64 notrap aligned #{ra}+8")
      if (arith = INT_ARITH[node.name])
        result, overflowed = @f.vals("#{arith[0]} #{a}, #{b}")
        big, small = @f.block.first, @f.block.first
        @f.ins "brif #{overflowed}, #{big}, #{small}"
        @f.switch(small)
        @f.ins "store notrap aligned #{int}, #{out_at}"
        @f.ins "store notrap aligned #{result}, #{out_at}+8"
        @f.ins "jump #{join}"
        @f.switch(big)
        @f.ins "call #{@f.import(arith[1])}(#{la}, #{ra}, #{out_at})"
        @f.ins "jump #{join}"
      else
        answer = @f.val("icmp #{INT_COMPARE[node.name]} #{a}, #{b}")
        @f.ins "store notrap aligned #{@f.iconst("i8", Capi::TAG_BOOL)}, #{out_at}"
        @f.ins "store notrap aligned #{answer}, #{out_at}+8"
        @f.ins "jump #{join}"
      end
      @f.switch(slow)
      send(la, node.name, [Operand.new(rhs.at, false, rhs.immediate)], out_at)
      @f.ins "jump #{join}"
      @f.switch(join)
      Operand.new(out, true, false)
    end

    def lower_if(predicate, statements, otherwise, negate)
      truth = truthy(lower_expr(predicate))
      yes, no, join = @f.block.first, @f.block.first, @f.block.first
      result = @f.slot
      @f.ins "brif #{truth}, #{negate ? no : yes}, #{negate ? yes : no}"
      @f.switch(yes)
      arm(lower_statements(statements), result, join)
      @f.switch(no)
      arm(otherwise ? lower_expr(otherwise) : literal_nil, result, join)
      @f.switch(join)
      Operand.new(result, true, false)
    end

    # One arm's value into the shared result slot, unless the arm left
    # through a `return`.
    def arm(value, result, join)
      return if @f.terminated?

      move(value, addr_of(result))
      @f.ins "jump #{join}"
    end

    def lower_while(predicate, statements, negate)
      mark = @f.val("call #{@f.import("zeo_rt_pool_mark")}()")
      head, body, done = @f.block.first, @f.block.first, @f.block.first
      @f.ins "jump #{head}"
      @f.switch(head)
      status_check(@f.val("call #{@f.import("zeo_rt_check_ints")}()"))
      truth = truthy(lower_expr(predicate))
      @f.ins "brif #{truth}, #{negate ? done : body}, #{negate ? body : done}"
      @f.switch(body)
      (statements&.body || []).each do |s|
        set_line(s)
        discard(lower_expr(s))
        break if @f.terminated?
      end
      unless @f.terminated?
        @f.ins "call #{@f.import("zeo_rt_pool_reset")}(#{mark})"
        @f.ins "jump #{head}"
      end
      @f.switch(done)
      @f.ins "call #{@f.import("zeo_rt_pool_reset")}(#{mark})"
      literal_nil
    end

    def lower_return(node)
      raise Unsupported.new(node, "a return outside a def") unless @kind == :body

      args = node.arguments&.arguments || []
      raise Unsupported.new(node, "a return of several values") if args.size > 1

      move(args.empty? ? literal_nil : lower_expr(args[0]), @out)
      @f.ins "jump #{@done}"
      # Nothing runs after the jump; the slot is never written or read.
      Operand.new(@f.slot, false, true)
    end

    # ---- values and ownership ----

    def addr_of(operand_or_slot)
      at = operand_or_slot.is_a?(Operand) ? operand_or_slot.at : operand_or_slot
      at.start_with?("ss") ? @f.val("stack_addr.i64 #{at}") : at
    end

    def zeroed_slot
      slot = @f.slot
      store_nil(addr_of(slot))
      slot
    end

    def store_nil(at)
      zero = @f.iconst("i64", 0)
      @f.ins "store notrap aligned #{zero}, #{at}"
      @f.ins "store notrap aligned #{zero}, #{at}+8"
      @f.ins "store notrap aligned #{zero}, #{at}+16"
    end

    def copy(from, to)
      [0, 8, 16].each do |off|
        word = @f.val("load.i64 notrap aligned #{from}#{off.zero? ? "" : "+#{off}"}")
        @f.ins "store notrap aligned #{word}, #{to}#{off.zero? ? "" : "+#{off}"}"
      end
    end

    def tag_of(at)
      @f.val("load.i8 notrap aligned #{at}")
    end

    # `call sym(at)` only when the value at `at` is a heap object.
    def if_heap(at, sym)
      heap = @f.val("icmp uge #{tag_of(at)}, #{@f.iconst("i8", Capi::TAG_HEAP)}")
      yes, no = @f.block.first, @f.block.first
      @f.ins "brif #{heap}, #{yes}, #{no}"
      @f.switch(yes)
      @f.ins "call #{@f.import(sym)}(#{at})"
      @f.ins "jump #{no}"
      @f.switch(no)
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
      @f.val("call #{@f.import("zeo_rt_truthy")}(#{borrow(value)})")
    end

    # A pointer into rodata and the byte length, for `text`.
    def rodata_ref(f, base, text)
      off = @program.intern(text)
      ptr = off.zero? ? base : f.val("iadd.i64 #{base}, #{f.iconst("i64", off)}")
      [ptr, f.iconst("i64", text.bytesize)]
    end

    def status_check(status)
      cont = @f.block.first
      @f.ins "brif #{status}, #{@raise}, #{cont}"
      @f.switch(cont)
    end
  end
end
