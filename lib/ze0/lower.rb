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

    # The two halves of a name that an operator assignment both reads and
    # writes.
    Target = Struct.new(:read, :write)

    def initialize(program)
      @program = program
      # Methods by owner and then by `[name, singleton]`, so a class's
      # `bar` and the top level's do not collide, and neither do `def x`
      # and `def self.x`. `@classes` is in declaration order.
      @defs = { Names::OBJECT => {} }
      @classes = {}
      @scopes = []
      @blocks = 0
      # Every name any class body marked `private_constant`. A read of a
      # name no body marks can never need the guard, whatever its scope.
      @private_constants = {}
    end

    def lower(root)
      statements = body_statements(root.statements)
      declare(statements, Names::OBJECT)
      @defs.each_value { |by_key| by_key.each_value { |d| lower_def(d) } }
      @classes.each_value { |c| lower_class_body(c) }
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
    def owner = @scopes.last.owner
    def raise_block = @scopes.last.raise_block
    def done_block = @scopes.last.done_block

    # ---- declarations ----

    # One walk over a body, collecting what lowering has to know before it
    # starts. Today that is the `def`s, so a call written above a
    # definition still resolves to it; classes and captures join them.
    def declare(statements, owner)
      # A bare `private` or `protected` is a mode over the `def`s BELOW
      # it, so the walk carries it. Every top-level `def` is a private
      # method of Object, whatever the body says.
      visibility = "public"
      statements.each do |s|
        case s
        when Prism::DefNode then declare_def(s, owner, visibility)
        when Prism::ClassNode then declare_class(s, owner, "class")
        when Prism::ModuleNode then declare_class(s, owner, "module")
        when Prism::CallNode then visibility = declare_macro(s, owner, visibility)
        end
      end
    end

    # `attr_reader`, its two siblings, and the visibility verbs: the class
    # body macros ze0 answers at COMPILE time. Anything else keeps the
    # refusal `lower_call` gives it.
    ACCESSORS = { attr_reader: :reader, attr_writer: :writer, attr_accessor: :accessor }.freeze
    VISIBILITY = %w[public private protected].freeze

    def declare_macro(node, owner, visibility)
      return visibility if owner == Names::OBJECT || !node.receiver.nil?

      name = node.name.to_s
      args = node.arguments&.arguments || []
      if VISIBILITY.include?(name)
        # `private :x` is positional and retags one name where it is
        # written; only the bare verb is a mode. `private def x` declares
        # the method at that visibility and nothing runs at all.
        return name if args.empty?

        args.each { |a| declare_def(a, owner, name) if a.is_a?(Prism::DefNode) }
        return visibility
      end
      if name == "private_constant"
        names = accessor_names(node, args)
        names.each { |n| @private_constants[n] = true }
        @classes.fetch(owner)[:private_constants].concat(names)
        return visibility
      end

      kind = ACCESSORS[node.name]
      return visibility unless kind

      accessor_names(node, args).each { |n| declare_accessor(node, owner, n, kind, visibility) }
      visibility
    end

    # The names an `attr_*` or positional visibility call names. Each has
    # to be a plain Symbol: ze0 emits a method per name at compile time,
    # so a String or a computed one has nothing to emit.
    def accessor_names(node, args)
      args.map do |a|
        raise Unsupported.new(a, "a `#{node.name}` argument of that shape") unless a.is_a?(Prism::SymbolNode)

        a.unescaped
      end
    end

    # One generated accessor: a method row like any other `def`, with no
    # body function at all. The trampoline IS the method.
    def declare_accessor(node, owner, name, kind, visibility)
      readers = kind == :writer ? [] : [[name, :reader, []]]
      writers = kind == :reader ? [] : [["#{name}=", :writer, [["req", ""]]]]
      (readers + writers).each do |method, half, params|
        key = [method.to_sym, false]
        raise Unsupported.new(node, "a def named twice") if @defs.fetch(owner).key?(key)

        @defs[owner][key] = {
          accessor: half, ivar: name, owner: owner, singleton: false,
          name: method, line: node.location.start_line,
        }
        @program.add_def(
          name: method,
          tramp: trampoline_of(owner, method, false),
          params: params,
          line: node.location.start_line,
          owner: owner,
          singleton: false,
          visibility: visibility,
        )
      end
    end

    # A class or module, and everything its body declares. The backend
    # assigns the id; ze0 only ever names it, by the path it is written
    # at -- `Ze0::Lower`, which is what `Module#name` answers.
    def declare_class(node, owner, kind)
      raise Unsupported.new(node, "a scoped class name") unless node.constant_path.is_a?(Prism::ConstantReadNode)

      name = qualify(owner, node.name.to_s)
      raise Unsupported.new(node, "a class named twice") if @classes.key?(name)

      superclass = superclass_of(node, owner, kind)
      body = body_statements(node.body)
      # The body's symbol is settled here, not when it is lowered: an
      # enclosing body calls it, and the two are lowered in either order.
      ivars = ivar_names(body, superclass)
      private_constants = []
      @classes[name] = {
        name: name, kind: kind, node: node, body: body, ivars: ivars,
        private_constants: private_constants,
        symbol: "zeo_cb_#{Names.owner_fragment(name)}",
      }
      @defs[name] = {}
      @program.add_class(
        name: name,
        superclass: superclass,
        kind: kind,
        ivars: ivars,
        private_constants: private_constants,
      )
      declare(body, name)
    end

    # `Outer::Inner`, or the bare name at the top level.
    def qualify(owner, name)
      owner == Names::OBJECT ? name : "#{owner}::#{name}"
    end

    def superclass_of(node, owner, kind)
      return Names::OBJECT if kind == "module" || node.superclass.nil?
      unless node.superclass.is_a?(Prism::ConstantReadNode)
        raise Unsupported.new(node.superclass, "a superclass of that shape")
      end

      # A name this program does not declare goes through as written: the
      # backend resolves it against the builtin exceptions, whose ids it
      # owns, and refuses every other builtin -- `class Foo < String` is a
      # different native shape.
      resolve_class(owner, node.superclass.name.to_s) || node.superclass.name.to_s
    end

    # A class name as written, resolved outward from `owner`: `Lower`
    # inside `Ze0` is `Ze0::Lower` before it is a top-level `Lower`.
    def resolve_class(owner, name)
      scopes = owner == Names::OBJECT ? [] : owner.split("::")
      scopes.size.downto(0)
            .map { |n| qualify(scopes.first(n).join("::").then { |o| o.empty? ? Names::OBJECT : o }, name) }
            .find { |candidate| @classes.key?(candidate) }
    end

    # The instance variables a class declares, in slot order: the ones a
    # superclass already declared, then the ones this body's methods name
    # in first-mention order. Parent first, so a slot index an inherited
    # method was compiled with still reads the same variable here.
    #
    # The names go in WITHOUT their `@`, which is the spelling
    # `ClassDesc.ivar_names` holds and `instance_variables` puts back.
    def ivar_names(body, superclass)
      found = {}
      @classes[superclass]&.fetch(:ivars)&.each { |n| found[n] = true }
      body.each { |n| ivars_under(n, found) }
      found.keys
    end

    IVAR_NODES = [
      Prism::InstanceVariableReadNode, Prism::InstanceVariableWriteNode,
      Prism::InstanceVariableOperatorWriteNode, Prism::InstanceVariableOrWriteNode,
      Prism::InstanceVariableAndWriteNode, Prism::InstanceVariableTargetNode,
    ].freeze

    def ivars_under(node, found)
      found[node.name.to_s.delete_prefix("@")] = true if IVAR_NODES.any? { |k| node.is_a?(k) }
      # An `attr_reader :x` names no `@x` anywhere, and still declares its
      # slot: the generated accessor reads the slot by index.
      if node.is_a?(Prism::CallNode) && node.receiver.nil? && ACCESSORS.key?(node.name)
        accessor_names(node, node.arguments&.arguments || []).each { |n| found[n] = true }
      end
      node.compact_child_nodes.each { |c| ivars_under(c, found) }
      found
    end

    # A Prism parameter list as the shape the binder and the body agree
    # on. A destructuring parameter is refused: it binds names the slot
    # array has no room for.
    def parse_params(node)
      return Params.new([], [], nil, [], [], nil, nil, false) if node.nil?

      node.requireds.each { |r| refuse_destructure(r) }
      node.posts.each { |r| refuse_destructure(r) }
      Params.new(
        node.requireds.map(&:name),
        node.optionals.map { |o| Params::Optional.new(o.name, o.value) },
        rest_of(node.rest),
        node.posts.map(&:name),
        node.keywords.map { |k| keyword_of(k) },
        kwrest_of(node.keyword_rest),
        node.block&.name,
        node.keyword_rest.is_a?(Prism::NoKeywordsParameterNode),
      )
    end

    def refuse_destructure(node)
      raise Unsupported.new(node, "a destructuring parameter") unless node.is_a?(Prism::RequiredParameterNode)
    end

    def rest_of(node)
      return nil if node.nil?
      raise Unsupported.new(node, "an implicit rest") unless node.is_a?(Prism::RestParameterNode)

      Params::Star.new(node.name)
    end

    def kwrest_of(node)
      return nil if node.nil? || node.is_a?(Prism::NoKeywordsParameterNode)
      raise Unsupported.new(node, "a forwarding parameter") unless node.is_a?(Prism::KeywordRestParameterNode)

      Params::Star.new(node.name)
    end

    def keyword_of(node)
      case node
      when Prism::RequiredKeywordParameterNode then Params::Keyword.new(node.name, nil, true)
      when Prism::OptionalKeywordParameterNode then Params::Keyword.new(node.name, node.value, false)
      else raise Unsupported.new(node, "a keyword parameter of that shape")
      end
    end

    def declare_def(node, owner, visibility = "public")
      singleton = node.receiver.is_a?(Prism::SelfNode)
      raise Unsupported.new(node, "a def with a receiver") if node.receiver && !singleton
      raise Unsupported.new(node, "a def on self at the top level") if singleton && owner == Names::OBJECT
      key = [node.name, singleton]
      raise Unsupported.new(node, "a def named twice") if @defs.fetch(owner).key?(key)

      params = parse_params(node.parameters)
      @defs[owner][key] = {
        params: params, node: node, block: params.takes_block?(uses_block?(node.body)),
        owner: owner, singleton: singleton,
      }
      @program.add_def(
        name: node.name,
        tramp: trampoline_of(owner, node.name, singleton),
        params: params.rows,
        line: node.location.start_line,
        owner: owner == Names::OBJECT ? "" : owner,
        singleton: singleton,
        visibility: visibility,
      )
    end

    # A `def` in statement position answers its own name, and the
    # declaration pass has already emitted it. The pass walks only the
    # statements of a program, class or module body, so a `def` written
    # anywhere else -- inside a block, an `if`, a loop or another `def` --
    # would be DEFINED by ruby and dropped here.
    def declared_def(node)
      singleton = node.receiver.is_a?(Prism::SelfNode)
      found = @defs.fetch(owner, {})[[node.name, singleton]]
      raise Unsupported.new(node, "a def nested inside another statement") unless found&.fetch(:node).equal?(node)

      literal_symbol(node.name)
    end

    def body_symbol_of(owner, name, singleton)
      singleton ? Names.class_method_symbol(owner, name) : Names.method_symbol(owner, name)
    end

    def trampoline_of(owner, name, singleton)
      singleton ? Names.class_trampoline_symbol(owner, name) : Names.trampoline_symbol(owner, name)
    end

    def label_of(owner, name, singleton)
      singleton ? Names.class_method_label(owner, name) : Names.method_label(owner, name)
    end

    # ---- captures ----
    #
    # The crude rule the Rust emitter's 1,270-line analysis exists to
    # refine: a name is boxed when any block written in the scope mentions
    # it. That over-boxes -- a name a block only reads and nobody assigns
    # needs no cell -- and it is never wrong.

    # The locals of this scope that a block under `nodes` names.
    def captured_names(nodes, owned)
      mentioned = {}
      nodes.each { |n| blocks_under(n).each { |b| names_under(b, mentioned) } }
      owned.select { |n| mentioned.key?(n) }
    end

    def blocks_under(node, found = [])
      found << node if node.is_a?(Prism::BlockNode)
      node.compact_child_nodes.each { |c| blocks_under(c, found) }
      found
    end

    LOCAL_NODES = [
      Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode,
      Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode,
      Prism::LocalVariableAndWriteNode, Prism::LocalVariableTargetNode,
    ].freeze

    # Whether a body reaches for its call-site block. A block literal
    # written INSIDE it has its own, so only a bare `yield` or
    # `block_given?` counts -- and neither can appear in a nested `def`,
    # which ze0 refuses anyway.
    def uses_block?(node)
      return false if node.nil?
      return true if node.is_a?(Prism::YieldNode)
      # `super` forwards the caller's block whether or not the method
      # names one, so the signature has to carry it here too -- without
      # the parameter the trampoline releases it and it is gone.
      return true if node.is_a?(Prism::SuperNode) || node.is_a?(Prism::ForwardingSuperNode)
      return true if node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == :block_given?

      node.compact_child_nodes.any? { |c| uses_block?(c) }
    end

    def names_under(node, found = {})
      found[node.name] = true if LOCAL_NODES.any? { |k| node.is_a?(k) }
      node.compact_child_nodes.each { |c| names_under(c, found) }
      found
    end

    # A bare call ze0 may lower as a DIRECT call to a body, skipping
    # dispatch.
    #
    # Only in a program with no classes. Once one exists, the name a bare
    # call resolves to is a run-time fact: `describe` calling `speak`
    # inside `Animal` must reach `Dog#speak` for a Dog, and deciding that
    # statically needs an override analysis ze0 does not have. Every call
    # in such a program takes the dynamic send, which is slower and right.
    def visible_def(name)
      return nil unless @classes.empty?

      @defs[Names::OBJECT][[name, false]]
    end

    # ---- functions ----

    # Lower `function` as a new scope, and answer it to the caller once the
    # body has left the stack.
    def in_scope(function, kind)
      @scopes.push(Scope.new(function, kind))
      yield
      @scopes.pop.f
    end

    def lower_def(definition)
      return lower_accessor(definition) if definition[:accessor]

      node = definition[:node]
      owner, singleton = definition[:owner], definition[:singleton]
      params = definition[:params]
      names = params.slot_names
      takes_block = definition[:block]
      body_sym = body_symbol_of(owner, node.name, singleton)
      arity = names.size + (takes_block ? 3 : 2)
      function = Clif::Function.new(body_sym, ["i64"] * arity, "i32")
      in_scope(function, :body) do
        scope.owner = owner
        scope.definition = definition
        scope.self_operand = Operand.new(f.args[0], false, false)
        scope.blk = f.args[names.size + 1] if takes_block
        scope.out = f.args.last
        prologue
        own = names + (node.locals - names)
        boxed = captured_names(body_statements(node.body), own)
        own.each { |n| declare_local(n, boxed: boxed.include?(n)) }
        status = f.val("call #{f.import("zeo_rt_stack_check")}()")
        overflow, cont = f.label, f.label
        f.ins "brif #{status}, #{overflow}, #{cont}"
        f.switch(overflow)
        f.ins "return #{f.iconst("i32", 1)}"
        f.switch(cont)
        bind_slots(params, names)
        bind_block_parameter(params.block) if params.block
        scope.frame_base = label_of(owner, node.name, singleton)
        enter_frame(scope.frame_label, node.location.start_line, node.location.end_line)
        value = lower_statements(node.body)
        move(value, out) unless f.terminated?
        f.ins "jump #{done_block}" unless f.terminated?
        epilogue
      end
      @program.add_function(label_of(owner, node.name, singleton), function)
      if params.plain?
        lower_trampoline(definition, names.size)
      else
        lower_bound_trampoline(definition, params, names.size)
      end
    end

    # An `attr_*`-generated accessor, which in ruby is ISEQ-LESS: it holds
    # no frame, appears in no backtrace, and its own wrong-arity raise is
    # reported at the caller's line. So there is no body function and no
    # frame push -- the trampoline is the whole method, an arity check and
    # one slot access (`clif/params.rs`'s `define_accessor`).
    #
    # The Rust emitter also writes a `REG_ACCESSOR_SLOT` row beside it, so
    # a call site caches the SLOT instead of this trampoline. ze0 does not:
    # the row names its class by ID, which a front end never learns. The
    # row is registration data and the method table still carries the
    # trampoline, so leaving it out costs a cache hit and answers the same.
    def lower_accessor(definition)
      owner, name, writer = definition[:owner], definition[:name], definition[:accessor] == :writer
      ivar = definition[:ivar]
      # An exception subclass's instances are the runtime's own
      # `RubyException`, which declares no slots at all: a slot write on
      # one is dropped. Its accessor reaches the name-keyed store, which
      # is what the Rust emitter falls back to for a native-backed class.
      keyed = native_backed?(owner)
      function = Clif::Function.new(trampoline_of(owner, name, false), ["i64"] * 5, "i32")
      in_scope(function, :trampoline) do
        recv, argv, argc, blk, into = f.args
        scope.rodata = f.val("symbol_value.i64 #{f.symbol("zeo_rodata")}") if keyed
        release_block_argument(blk)
        want = f.iconst("i64", writer ? 1 : 0)
        fits = f.val("icmp eq #{argc}, #{want}")
        go, wrong = f.label, f.label
        f.ins "brif #{fits}, #{go}, #{wrong}"
        f.switch(wrong)
        f.ins "return #{f.val("call #{f.import("zeo_rt_wrong_arity")}(#{argc}, #{want}, #{want})")}"
        f.switch(go)
        if keyed
          keyed_accessor(ivar, recv, argv, into, writer)
        else
          slot_accessor(@program.ivar_slot(owner, ivar), recv, argv, into, writer)
        end
      end
      @program.add_function(label_of(owner, name, false), function)
    end

    def slot_accessor(slot, recv, argv, into, writer)
      at = f.iconst("i64", slot)
      unless writer
        f.ins "call #{f.import("zeo_rt_ivar_get_slot")}(#{recv}, #{at}, #{into})"
        return f.ins("return #{f.iconst("i32", 0)}")
      end

      status_return(f.val("call #{f.import("zeo_rt_frozen_check")}(#{recv})"))
      # Two fresh references off the caller's borrowed argument: one moves
      # into the slot, one is the value the writer answers.
      retain_if_heap(argv)
      retain_if_heap(argv)
      copy(argv, into)
      f.ins "return #{f.val("call #{f.import("zeo_rt_ivar_set_slot")}(#{recv}, #{at}, #{argv})")}"
    end

    def keyed_accessor(ivar, recv, argv, into, writer)
      ptr, len = rodata_ref(ivar)
      box = f.iconst("i32", Capi::MAIN_BOX)
      unless writer
        return f.ins("return #{f.val("call #{f.import("zeo_rt_ivar_get_dyn")}(#{recv}, #{ptr}, #{len}, #{box}, #{into})")}")
      end

      # The set BORROWS its value and does its own frozen check, so the
      # answer takes the one fresh reference.
      status_return(f.val("call #{f.import("zeo_rt_ivar_set_dyn")}(#{recv}, #{ptr}, #{len}, #{box}, #{argv})"))
      retain_if_heap(argv)
      copy(argv, into)
      f.ins "return #{f.iconst("i32", 0)}"
    end

    # Whether instances of `owner` are a runtime type rather than a
    # generated object with slots, which a builtin superclass makes them.
    def native_backed?(owner)
      entry = @classes.fetch(owner)
      return false if entry[:kind] == "module"

      up = @program.superclass_of(owner)
      up != Names::OBJECT && (!@classes.key?(up) || native_backed?(up))
    end

    # Leave with the signal this status reports, or carry on. A trampoline
    # has no landing block of its own: the caller's does the unwinding.
    def status_return(status)
      out, cont = f.label, f.label
      f.ins "brif #{status}, #{out}, #{cont}"
      f.switch(out)
      f.ins "return #{f.iconst("i32", 1)}"
      f.switch(cont)
    end

    # The trampoline of a shape the runtime's binder has to route: it
    # builds the slot array, hands `argv` to `zeo_rt_bind_params`, and
    # passes one pointer per slot -- NULL where an optional was left out,
    # so the body runs its default.
    def lower_bound_trampoline(definition, params, n_slots)
      node = definition[:node]
      owner, singleton = definition[:owner], definition[:singleton]
      takes_block = definition[:block]
      function = Clif::Function.new(trampoline_of(owner, node.name, singleton), ["i64"] * 5, "i32")
      in_scope(function, :trampoline) do
        recv, argv, argc, blk, into = f.args
        scope.rodata = f.val("symbol_value.i64 #{f.symbol("zeo_rodata")}")
        desc = param_desc(params, node.name.to_s, label_of(owner, node.name, singleton), node)
        slots = n_slots.zero? ? nil : f.slot(Capi::SLOT_BYTES * n_slots)
        slots_at = slots ? addr_of(slots) : f.iconst("i64", 0)
        present = f.slot(8)
        status = f.val(
          "call #{f.import("zeo_rt_bind_params")}(#{addr_of(desc)}, #{argv}, #{argc}, " \
          "#{slots_at}, #{addr_of(present)})",
        )
        ok, bad = f.label, f.label
        f.ins "brif #{status}, #{bad}, #{ok}"
        f.switch(bad)
        # The binder leaves every slot nil on an error, so only the block
        # it was handed still needs releasing.
        release_block_argument(blk)
        f.ins "return #{f.iconst("i32", 1)}"
        f.switch(ok)
        release_block_argument(blk) unless takes_block
        bits = f.val("load.i64 notrap aligned #{addr_of(present)}")
        addresses = (0...n_slots).map do |i|
          at = i.zero? ? slots_at : f.stack_addr("#{slots}+#{i * Capi::SLOT_BYTES}")
          next at unless params.optional_slots.include?(i)

          # An absent optional is a null pointer, which is how the body
          # tells "left out" from "given nil".
          got = f.val("band #{bits}, #{f.iconst("i64", 1 << i)}")
          f.val("select #{f.val("icmp ne #{got}, #{f.iconst("i64", 0)}")}, #{at}, #{f.iconst("i64", 0)}")
        end
        handed = takes_block ? addresses + [blk] : addresses
        n_params = n_slots + (takes_block ? 3 : 2)
        body = f.callee(body_symbol_of(owner, node.name, singleton), ["i64"] * n_params, "i32")
        status = f.val("call #{body}(#{([recv] + handed + [into]).join(", ")})")
        # The slots hold the binder's owned copies; the body took its own.
        (0...n_slots).each do |i|
          at = i.zero? ? slots_at : f.stack_addr("#{slots}+#{i * Capi::SLOT_BYTES}")
          f.ins "call #{f.import("zeo_rt_release")}(#{at})"
        end
        f.ins "return #{status}"
      end
      @program.add_function("trampoline", function)
    end

    # Each slot's value into its local. An optional slot arrives as a NULL
    # pointer when the caller left it out, and the default expression runs
    # here rather than at the call -- which is what lets one default read
    # the parameter before it.
    def bind_slots(params, names)
      defaults = params.defaults.to_h
      names.each_with_index do |n, i|
        local = locals.fetch(n)
        argument = f.args[i + 1]
        unless defaults.key?(i)
          initialize_local(local, argument)
          next
        end

        given, absent, join = f.label, f.label, f.label
        f.ins "brif #{f.val("icmp ne #{argument}, #{f.iconst("i64", 0)}")}, #{given}, #{absent}"
        f.switch(given)
        initialize_local(local, argument)
        f.ins "jump #{join}"
        f.switch(absent)
        store_local(local, lower_expr(defaults[i]))
        f.ins "jump #{join}" unless f.terminated?
        f.switch(join)
      end
    end

    # `&b`: not a slot, but the block channel itself, which is nil when
    # the caller passed none. The body already owns the moved-in block, so
    # the local takes a reference of its own.
    def bind_block_parameter(name)
      local = locals.fetch(name)
      given, join = f.label, f.label
      f.ins "brif #{f.val("icmp ne #{scope.blk}, #{f.iconst("i64", 0)}")}, #{given}, #{join}"
      f.switch(given)
      initialize_local(local, scope.blk)
      f.ins "jump #{join}"
      f.switch(join)
    end

    # The `ValueFn` the runtime dispatches to: releases a block it was
    # handed, checks the count, and calls the body on the argument slots.
    def lower_trampoline(definition, arity)
      node = definition[:node]
      owner, singleton = definition[:owner], definition[:singleton]
      takes_block = definition[:block]
      function = Clif::Function.new(trampoline_of(owner, node.name, singleton), ["i64"] * 5, "i32")
      in_scope(function, :trampoline) do
        recv, argv, argc, blk, into = f.args
        scope.rodata = f.val("symbol_value.i64 #{f.symbol("zeo_rodata")}")
        # A body that uses a block takes it as a parameter and releases it
        # itself; one that does not must release it here, since the block
        # was moved in either way.
        release_block_argument(blk) unless takes_block
        n = f.iconst("i64", arity)
        fits = f.val("icmp eq #{argc}, #{n}")
        go, wrong = f.label, f.label
        f.ins "brif #{fits}, #{go}, #{wrong}"
        f.switch(wrong)
        file, file_len = rodata_ref(@program.file)
        label, label_len = rodata_ref(label_of(owner, node.name, singleton))
        line = f.iconst("i32", node.location.start_line)
        end_line = f.iconst("i32", node.location.end_line)
        f.ins "call #{f.import("zeo_rt_frame_push")}(#{file}, #{file_len}, #{label}, #{label_len}, #{line}, #{end_line})"
        release_block_argument(blk) if takes_block
        status = f.val("call #{f.import("zeo_rt_wrong_arity")}(#{argc}, #{n}, #{n})")
        f.ins "call #{f.import("zeo_rt_frame_pop")}()"
        f.ins "return #{status}"
        f.switch(go)
        args = (0...arity).map do |i|
          i.zero? ? argv : f.val("iadd.i64 #{argv}, #{f.iconst("i64", i * Capi::SLOT_BYTES)}")
        end
        n_params = arity + (takes_block ? 3 : 2)
        body = f.callee(body_symbol_of(owner, node.name, singleton), ["i64"] * n_params, "i32")
        handed = takes_block ? args + [blk] : args
        status = f.val("call #{body}(#{([recv] + handed + [into]).join(", ")})")
        f.ins "return #{status}"
      end
      @program.add_function("trampoline", function)
    end

    # A class or module body is its own function with the class as `self`,
    # called at the statement's position. A `def` inside it registers
    # statically and only leaves its name behind, which is what ruby
    # answers for one.
    def lower_class_body(entry)
      symbol = entry[:symbol]
      node = entry[:node]
      function = Clif::Function.new(symbol, ["i64", "i64"], "i32")
      in_scope(function, :class_body) do
        scope.owner = entry[:name]
        scope.self_operand = Operand.new(f.args[0], false, false)
        scope.out = f.args[1]
        prologue
        boxed = captured_names(entry[:body], node.locals)
        node.locals.each { |n| declare_local(n, boxed: boxed.include?(n)) }
        scope.frame_base = Names.body_label(entry[:name], entry[:kind])
        enter_frame(scope.frame_label, node.location.start_line, node.location.end_line)
        value = lower_statements(node.body)
        move(value, out) unless f.terminated?
        f.ins "jump #{done_block}" unless f.terminated?
        epilogue
      end
      @program.add_function(symbol, function)
    end

    # `class Foo ... end` in statement position: the class is already
    # registered, so this reads it and runs its body.
    def lower_class_statement(node)
      name = qualify(owner, node.name.to_s)
      entry = @classes.fetch(name) { raise Unsupported.new(node, "a class this program does not declare") }
      klass = constant_named(node.name.to_s)
      result = f.slot
      body = f.callee(entry[:symbol], ["i64", "i64"], "i32")
      status_check(f.val("call #{body}(#{borrow(klass)}, #{addr_of(result)})"))
      Operand.new(result, true, false)
    end

    def lower_toplevel(statements, names)
      function = Clif::Function.new(Names::TOPLEVEL, ["i64"], "i32")
      in_scope(function, :toplevel) do
        scope.out = f.args[0]
        prologue
        boxed = captured_names(statements, names)
        names.each { |n| declare_local(n, boxed: boxed.include?(n)) }
        scope.frame_base = "<main>"
        enter_frame(scope.frame_label, 0, 0)
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
      release_block_argument(scope.blk) if scope.blk
      f.ins "call #{f.import("zeo_rt_frame_pop")}()"
      f.ins "return #{scope.status}"
    end

    # A block literal as its own CLIF function, the runtime's `BlockFn`:
    # `(env, self, argv, argc, blk, out) -> i32`. Note the shape is NOT the
    # five-pointer trampoline's -- a block fn prepends `env` and takes its
    # `self` as a parameter, because `instance_exec` rebinds it per call.
    def lower_block(node, lambda_shape = false)
      raise Unsupported.new(node, "a block-local variable") if node.parameters&.locals&.any?

      params = parse_params(node.parameters&.parameters)
      names = params.slot_names
      # ruby spreads a single Array argument over a shape with real
      # positional structure; one bare parameter is ambiguous and never
      # splats (`clif/params.rs`'s `auto_splats`).
      auto_splat = !lambda_shape && auto_splats?(params)
      symbol = "zeo_blk_#{@blocks}"
      @blocks += 1
      function = Clif::Function.new(symbol, ["i64"] * 6, "i32")
      base, depth = scope.frame_base, scope.block_depth
      # The enclosing names this block reads. Both ends read this list in
      # the same order, so the creation site's array and the body's
      # `ProcEnv` rows line up.
      captures = block_captures(node, names)
      in_scope(function, :block) do
        scope.frame_base = base
        scope.block_depth = depth + 1
        env, slf, argv, argc, blk, into = f.args
        scope.env = env
        scope.self_operand = Operand.new(slf, false, false)
        scope.out = into
        prologue
        release_block_argument(blk)
        captures.each_with_index { |n, i| declare_captured(n, env, i) }
        own = names + (node.locals - names)
        boxed = captured_names(body_statements(node.body), own)
        own.each { |n| declare_local(n, boxed: boxed.include?(n)) }
        bind_block_params(params, names, argv, argc, node, auto_splat, lambda_shape)
        enter_frame(scope.frame_label, node.location.start_line, node.location.end_line)
        value = lower_statements(node.body)
        move(value, out) unless f.terminated?
        f.ins "jump #{done_block}" unless f.terminated?
        epilogue
      end
      @program.add_function(symbol, function)
      [symbol, captures]
    end

    # The names this block reads out of the scope that wrote it, sorted so
    # the order is the same on both sides of the `ProcEnv`.
    def block_captures(node, names)
      own = names + node.locals
      (names_under(node).keys - own).select { |n| locals.key?(n) }.sort
    end

    # The CALL-SITE block, moved in and so this body's to release.
    def release_block_argument(blk)
      has = f.val("icmp ne #{blk}, #{f.iconst("i64", 0)}")
      yes, no = f.label, f.label
      f.ins "brif #{has}, #{yes}, #{no}"
      f.switch(yes)
      f.ins "call #{f.import("zeo_rt_release")}(#{blk})"
      f.ins "jump #{no}"
      f.switch(no)
    end

    # Ruby's block binding is the runtime's, not a copy of it: lenient
    # positionals, auto-splat of a single Array argument when the shape has
    # real positional structure, and a lambda's strict arity.
    #
    # The binder reads a `ParamDescC`, which the Rust emitter writes into
    # rodata. ze0 cannot: the struct holds POINTERS, and a rodata blob a
    # sidecar carries as bytes has nowhere to put a relocation. So the
    # struct is built in a stack slot instead, which works because the
    # binder only reads it for the length of the call.

    # ruby spreads a single Array argument over a block whose shape has
    # real positional structure; one bare parameter is ambiguous and never
    # splats (`clif/params.rs`'s `auto_splats`).
    def auto_splats?(params)
      lead, opt, post = params.required.size, params.optional.size, params.post.size
      ambiguous = lead == 1 && opt.zero? && post.zero? && params.rest.nil?
      !ambiguous && (lead + post > 0 || opt > 1)
    end

    def bind_block_params(params, names, argv, argc, node, auto_splat, lambda_shape)
      return if names.empty?

      desc = param_desc(params, "block", scope.frame_label, node)
      slots = f.slot(Capi::SLOT_BYTES * names.size)
      present = f.slot(8)
      bits = auto_splat ? Capi::BLOCK_BIND_AUTO_SPLAT : 0
      bits |= Capi::BLOCK_BIND_LAMBDA if lambda_shape
      flags = f.iconst("i8", bits)
      status_check(f.val(
        "call #{f.import("zeo_rt_bind_block_params")}(#{addr_of(desc)}, #{flags}, #{argv}, #{argc}, " \
        "#{addr_of(slots)}, #{addr_of(present)})",
      ))
      present_bits = f.val("load.i64 notrap aligned #{addr_of(present)}")
      defaults = params.defaults.to_h
      # The binder writes an owned value into every bound slot, which the
      # local takes as it is; an unbound optional runs its default here.
      names.each_with_index do |n, i|
        from = i.zero? ? addr_of(slots) : f.stack_addr("#{slots}+#{i * Capi::SLOT_BYTES}")
        local = locals.fetch(n)
        unless defaults.key?(i)
          take_bound_slot(local, from)
          next
        end

        given, absent, join = f.label, f.label, f.label
        got = f.val("band #{present_bits}, #{f.iconst("i64", 1 << i)}")
        f.ins "brif #{f.val("icmp ne #{got}, #{f.iconst("i64", 0)}")}, #{given}, #{absent}"
        f.switch(given)
        take_bound_slot(local, from)
        f.ins "jump #{join}"
        f.switch(absent)
        store_local(local, lower_expr(defaults[i]))
        f.ins "jump #{join}" unless f.terminated?
        f.switch(join)
      end
    end

    # A slot the binder owns, taken by the local: a plain slot copies the
    # bytes as they are, a cell moves them in.
    def take_bound_slot(local, from)
      if local.boxed?
        f.ins "call #{f.import("zeo_rt_cell_store")}(#{cell_of(local)}, #{from})"
      else
        copy(from, addr_of(local.slot))
      end
    end

    # A `zeo_abi::abi::ParamDescC` on the stack, and the `KwParamC` rows it
    # points at. Offsets follow the structs' declaration order under
    # `repr(C)`; the binder reads both only for the length of the call.
    def param_desc(params, name, label, node)
      kws, n_kws = keyword_rows(params.keywords)
      slot = f.slot(PARAM_DESC_BYTES)
      at = addr_of(slot)
      put = ->(off, value) { f.ins "store notrap aligned #{value}, #{at}#{off.zero? ? "" : "+#{off}"}" }
      put.call(0, f.iconst("i32", params.required.size))
      put.call(4, f.iconst("i32", params.optional.size))
      put.call(8, f.iconst("i32", params.post.size))
      put.call(12, f.iconst("i8", star_of(params.rest)))
      put.call(13, f.iconst("i8", star_of(params.kwrest)))
      put.call(14, f.iconst("i8", params.no_keywords ? 1 : 0))
      put.call(15, f.iconst("i8", 0))
      put.call(16, kws)
      put.call(24, n_kws)
      [[32, name], [48, @program.file], [64, label]].each do |off, text|
        ptr, len = rodata_ref(text)
        put.call(off, ptr)
        put.call(off + 8, len)
      end
      put.call(80, f.iconst("i32", node.location.start_line))
      put.call(84, f.iconst("i32", node.location.end_line))
      slot
    end

    PARAM_DESC_BYTES = 88
    KW_PARAM_BYTES = 24

    def star_of(star)
      return Capi::PARAM_STAR_NONE if star.nil?

      star.named? ? Capi::PARAM_STAR_NAMED : Capi::PARAM_STAR_ANON
    end

    def keyword_rows(keywords)
      return [f.iconst("i64", 0), f.iconst("i64", 0)] if keywords.empty?

      slot = f.slot(KW_PARAM_BYTES * keywords.size)
      at = addr_of(slot)
      keywords.each_with_index do |kw, i|
        off = i * KW_PARAM_BYTES
        ptr, len = rodata_ref(kw.name.to_s)
        f.ins "store notrap aligned #{ptr}, #{at}#{off.zero? ? "" : "+#{off}"}"
        f.ins "store notrap aligned #{len}, #{at}+#{off + 8}"
        f.ins "store notrap aligned #{f.iconst("i8", kw.required ? 1 : 0)}, #{at}+#{off + 16}"
      end
      [at, f.iconst("i64", keywords.size)]
    end

    # ---- statements ----

    # The statements of a body. A `def` or block written with its own
    # `rescue` clause carries a `BeginNode` here instead of a list, and it
    # lowers as the one statement it is.
    def body_statements(node)
      return [] if node.nil?
      return [node] if node.is_a?(Prism::BeginNode)

      node.body
    end

    # The value of the last statement; every other one is discarded.
    def lower_statements(node)
      body = body_statements(node)
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
      when Prism::RegularExpressionNode then literal_regexp(node)
      when Prism::InterpolatedStringNode then interpolated_string(node)
      when Prism::ArrayNode then array_literal(node)
      when Prism::HashNode then hash_literal(node)
      when Prism::RangeNode then range_literal(node)
      when Prism::LocalVariableReadNode then local_read(node)
      when Prism::LocalVariableWriteNode then local_write(node)
      when Prism::MultiWriteNode then multi_write(node)
      when Prism::LocalVariableOperatorWriteNode, Prism::InstanceVariableOperatorWriteNode,
           Prism::GlobalVariableOperatorWriteNode, Prism::IndexOperatorWriteNode,
           Prism::CallOperatorWriteNode then operator_write(node)
      when Prism::LocalVariableOrWriteNode, Prism::InstanceVariableOrWriteNode,
           Prism::GlobalVariableOrWriteNode, Prism::IndexOrWriteNode,
           Prism::CallOrWriteNode then conditional_write(node, false)
      when Prism::LocalVariableAndWriteNode, Prism::InstanceVariableAndWriteNode,
           Prism::GlobalVariableAndWriteNode, Prism::IndexAndWriteNode,
           Prism::CallAndWriteNode then conditional_write(node, true)
      when Prism::GlobalVariableReadNode then global_read(node)
      when Prism::GlobalVariableWriteNode then global_write(node)
      when Prism::InstanceVariableReadNode then ivar_read(node)
      when Prism::InstanceVariableWriteNode then ivar_write(node)
      when Prism::ConstantReadNode then constant_read(node)
      when Prism::ConstantWriteNode then constant_write(node)
      when Prism::ConstantPathWriteNode then constant_path_write(node)
      when Prism::ConstantPathNode then constant_path_read(node)
      when Prism::AndNode then and_or(node.left, node.right, true)
      when Prism::OrNode then and_or(node.left, node.right, false)
      when Prism::CaseNode then lower_case(node)
      when Prism::LambdaNode then lower_lambda(node)
      when Prism::ClassNode, Prism::ModuleNode then lower_class_statement(node)
      when Prism::DefNode then declared_def(node)
      when Prism::SelfNode then Operand.new(self_operand.at, false, self_operand.immediate)
      when Prism::CallNode then lower_call(node)
      when Prism::IfNode then lower_if(node.predicate, node.statements, node.subsequent, false)
      when Prism::UnlessNode then lower_if(node.predicate, node.statements, node.else_clause, true)
      when Prism::WhileNode then lower_while(node.predicate, node.statements, false)
      when Prism::UntilNode then lower_while(node.predicate, node.statements, true)
      when Prism::ReturnNode then lower_return(node)
      when Prism::YieldNode then lower_yield(node)
      when Prism::SuperNode then lower_super(node, node.arguments&.arguments || [])
      when Prism::ForwardingSuperNode then lower_super(node, nil)
      when Prism::NextNode then lower_next(node)
      when Prism::BreakNode then lower_break(node)
      when Prism::BeginNode then lower_begin(node)
      when Prism::AliasMethodNode then lower_alias_statement(node)
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

    # Under `# frozen_string_literal: true` the entry interns, so two
    # equal literals are ONE frozen object; otherwise each evaluation
    # mints a fresh string that BORROWS the rodata bytes until a
    # mutation promotes the buffer.
    def literal_string(bytes)
      slot = f.slot
      ptr, len = rodata_ref(bytes)
      entry = @program.frozen_string_literal ? "zeo_rt_str_lit" : "zeo_rt_str_lit_ro"
      f.ins "call #{f.import(entry)}(#{ptr}, #{len}, #{f.iconst("i8", Capi::UTF8)}, #{addr_of(slot)})"
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

    # A `"a#{b}c"`: a fresh empty String, then each piece appended. The
    # destination goes to the pool at CREATION, not at the end, because an
    # interpolated piece runs `to_s` and can raise.
    def interpolated_string(node)
      slot = f.slot
      at = addr_of(slot)
      zero = f.iconst("i64", 0)
      f.ins "call #{f.import("zeo_rt_str_new")}(#{zero}, #{zero}, #{f.iconst("i8", Capi::UTF8)}, #{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      node.parts.each { |part| append_part(at, part) }
      Operand.new(slot, false, false)
    end

    def append_part(at, part)
      case part
      when Prism::StringNode
        return if part.unescaped.empty?

        ptr, len = rodata_ref(part.unescaped)
        f.ins "call #{f.import("zeo_rt_str_append_lit")}(#{at}, #{ptr}, #{len})"
      when Prism::EmbeddedStatementsNode
        append_value(at, lower_statements(part.statements))
      when Prism::EmbeddedVariableNode
        append_value(at, lower_expr(part.variable))
      # Adjacent literals (`"a" "b"`, or one written over two lines) are
      # ONE string, and prism nests them a level deeper.
      when Prism::InterpolatedStringNode
        part.parts.each { |inner| append_part(at, inner) }
      else raise Unsupported.new(part, "an interpolated piece of that shape")
      end
    end

    def append_value(at, value)
      status_check(f.val("call #{f.import("zeo_rt_str_append_value")}(#{at}, #{borrow(value)})"))
    end

    # `[a, b]`: the array is pooled at creation, so an element that raises
    # mid-build strands nothing. Each element is HANDED OVER -- the array
    # takes the reference.
    def array_literal(node)
      slot = f.slot
      at = addr_of(slot)
      f.ins "call #{f.import("zeo_rt_array_new")}(#{f.iconst("i64", node.elements.size)}, #{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      node.elements.each do |e|
        # `[*xs]` spreads through ruby's `to_a` rule, which the runtime
        # does; anything else is one element.
        unless e.is_a?(Prism::SplatNode)
          f.ins "call #{f.import("zeo_rt_array_push")}(#{at}, #{hand_over(lower_expr(e))})"
          next
        end
        raise Unsupported.new(e, "an anonymous splat") if e.expression.nil?

        status_check(f.val(
          "call #{f.import("zeo_rt_array_push_splat")}(#{at}, #{borrow(lower_expr(e.expression))})",
        ))
      end
      Operand.new(slot, false, false)
    end

    def hash_literal(node)
      slot = f.slot
      at = addr_of(slot)
      f.ins "call #{f.import("zeo_rt_hash_new")}(#{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      node.elements.each do |e|
        # `{**h}` merges h's pairs in place, through ruby's `to_hash`
        # rule. `**nil` is the "no keywords" spelling and adds nothing.
        if e.is_a?(Prism::AssocSplatNode)
          raise Unsupported.new(e, "an anonymous splat") if e.value.nil?

          status_check(f.val(
            "call #{f.import("zeo_rt_kw_splat_into")}(#{at}, #{borrow(lower_expr(e.value))})",
          ))
          next
        end
        raise Unsupported.new(e, "a hash element of that shape") unless e.is_a?(Prism::AssocNode)

        key = hand_over(lower_expr(e.key))
        value = hand_over(lower_expr(e.value))
        status_check(f.val("call #{f.import("zeo_rt_hash_set")}(#{at}, #{key}, #{value})"))
      end
      Operand.new(slot, false, false)
    end

    # `a..b`, `a...b`, and either end left out. Both ends go to the pool
    # before either is handed over: lowering the second can raise while the
    # first is still owned here.
    def range_literal(node)
      ends = [node.left, node.right].map do |n|
        next if n.nil?

        value = lower_expr(n)
        borrow(value)
        value
      end
      addrs = ends.map { |v| v ? hand_over(v) : f.iconst("i64", 0) }
      slot = f.slot
      excl = f.iconst("i8", node.exclude_end? ? 1 : 0)
      status_check(f.val(
        "call #{f.import("zeo_rt_range_new")}(#{addrs[0]}, #{addrs[1]}, #{excl}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # ---- assignment to a name that is also read ----

    # `x += 1`, `x ||= 1` and `x &&= 1` are a read, an operation and a
    # write of the same name, so each form is written once and asks the
    # node which pair of halves it names.
    def target_of(node)
      case node
      when Prism::IndexOrWriteNode, Prism::IndexAndWriteNode, Prism::IndexOperatorWriteNode
        return index_target(node)
      when Prism::CallOrWriteNode, Prism::CallAndWriteNode, Prism::CallOperatorWriteNode
        return call_target(node)
      end

      name = node.name
      case node
      when Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode,
           Prism::LocalVariableAndWriteNode
        local = locals.fetch(name) { raise Unsupported.new(node, "the local #{name} has no slot") }
        Target.new(-> { read_local(local) }, ->(v) { store_local(local, v) })
      when Prism::InstanceVariableOperatorWriteNode, Prism::InstanceVariableOrWriteNode,
           Prism::InstanceVariableAndWriteNode
        Target.new(-> { ivar_load(ivar_key(name)) }, ->(v) { store_ivar(ivar_key(name), v) })
      else
        Target.new(-> { global_load(name.to_s) }, ->(v) { store_global(name.to_s, v) })
      end
    end

    # `h[k] ||= v` and `x.y ||= v` read and write through a send, and the
    # receiver and the index are evaluated ONCE: both halves close over
    # the operands the pool is already holding.
    def index_target(node)
      recv = lower_expr(node.receiver)
      borrow(recv)
      args = (node.arguments&.arguments || []).map { |a| lower_expr(a) }
      args.each { |a| borrow(a) }
      Target.new(
        -> { send_value(recv, :[], args) },
        ->(v) { send_value(recv, :[]=, args + [v]) },
      )
    end

    def call_target(node)
      raise Unsupported.new(node, "a safe navigation write") if safe_navigation?(node)

      recv = lower_expr(node.receiver)
      borrow(recv)
      Target.new(
        -> { send_value(recv, node.read_name, []) },
        ->(v) { send_value(recv, node.write_name, [v]) },
      )
    end

    def send_value(recv, name, operands)
      slot = f.slot
      dynamic_send(borrow(recv), name, operands, addr_of(slot))
      Operand.new(slot, true, false)
    end

    def operator_write(node)
      target = target_of(node)
      name = node.binary_operator
      lhs = target.read.call
      rhs = lower_expr(node.value)
      target.write.call(inline_binary?(name) ? binary(name, lhs, rhs) : operator_send(name, lhs, rhs))
    end

    def operator_send(name, lhs, rhs)
      slot = f.slot
      dynamic_send(borrow(lhs), name, [rhs], addr_of(slot))
      Operand.new(slot, true, false)
    end

    # `x ||= v` answers `x` when it is truthy and never writes; `x &&= v`
    # is the same with the arms the other way round.
    def conditional_write(node, conjunction)
      target = target_of(node)
      current = target.read.call
      truth = truthy(current)
      result = f.slot
      keep, assign, join = f.label, f.label, f.label
      f.ins "brif #{truth}, #{conjunction ? assign : keep}, #{conjunction ? keep : assign}"
      f.switch(keep)
      arm(current, result, join)
      f.switch(assign)
      arm(target.write.call(lower_expr(node.value)), result, join)
      f.switch(join)
      Operand.new(result, true, false)
    end

    # ---- globals, constants and instance variables ----

    # Never assigned is nil, ruby's rule, so the read cannot fail.
    def global_read(node)
      global_load(node.name.to_s)
    end

    def global_load(name)
      slot = f.slot
      ptr, len = rodata_ref(name)
      f.ins "call #{f.import("zeo_rt_gvar_get")}(#{f.iconst("i32", Capi::MAIN_BOX)}, #{ptr}, #{len}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    # The table clones the value, so the operand keeps its own reference
    # and the assignment answers it. A read-only global raises.
    def global_write(node)
      store_global(node.name.to_s, lower_expr(node.value))
    end

    def store_global(name, value)
      at = borrow(value)
      ptr, len = rodata_ref(name)
      status_check(f.val(
        "call #{f.import("zeo_rt_gvar_assign")}(#{f.iconst("i32", Capi::MAIN_BOX)}, #{ptr}, #{len}, #{at})",
      ))
      Operand.new(value.at, false, value.immediate)
    end

    # Name-keyed, not slot-keyed: only a generated accessor names a slot,
    # and it knows its class. The name goes WITHOUT its `@`, which is the
    # spelling `ClassDesc.ivar_names` holds -- pass `@x` and the write
    # misses the declared slot, lands in the invented table, and
    # `instance_variables` answers `:@@x`.
    def ivar_read(node)
      ivar_load(ivar_key(node.name))
    end

    def ivar_key(name) = name.to_s.delete_prefix("@")

    def ivar_load(name)
      slot = f.slot
      ptr, len = rodata_ref(name)
      status_check(f.val(
        "call #{f.import("zeo_rt_ivar_get_dyn")}(#{borrow(self_operand)}, #{ptr}, #{len}, " \
        "#{f.iconst("i32", Capi::MAIN_BOX)}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    def ivar_write(node)
      store_ivar(ivar_key(node.name), lower_expr(node.value))
    end

    def store_ivar(name, value)
      at = borrow(value)
      ptr, len = rodata_ref(name)
      status_check(f.val(
        "call #{f.import("zeo_rt_ivar_set_dyn")}(#{borrow(self_operand)}, #{ptr}, #{len}, " \
        "#{f.iconst("i32", Capi::MAIN_BOX)}, #{at})",
      ))
      Operand.new(value.at, false, value.immediate)
    end

    # A bare `Foo` walks the cref chain, which at the top level is Object
    # alone. A miss is ruby's NameError, naming the qualified spelling.
    def constant_read(node)
      constant_named(node.name.to_s)
    end

    # `Outer::Inner = value`. The scope has to be a class this program
    # declares, because the runtime takes the owner as an id and only a
    # compiled class has one ze0 can name.
    def constant_path_write(node)
      scope = node.target.parent
      unless scope.is_a?(Prism::ConstantReadNode) && (found = resolve_class(owner, scope.name.to_s))
        raise Unsupported.new(node, "a constant assigned into a scope this program does not define")
      end

      value = lower_expr(node.value)
      at = borrow(value)
      nptr, nlen = rodata_ref(node.target.name.to_s)
      fptr, flen = rodata_ref(@program.file)
      f.ins "call #{f.import("zeo_rt_const_set_at")}(#{class_id(found)}, #{nptr}, #{nlen}, " \
            "#{at}, #{fptr}, #{flen}, #{f.iconst("i32", node.location.start_line)}, " \
            "#{f.iconst("i32", Capi::MAIN_BOX)})"
      Operand.new(value.at, false, value.immediate)
    end

    # The `/n`, `/e`, `/s` and `/u` suffixes; without one a regexp takes
    # the source's encoding.
    def regexp_encoding(node)
      return Capi::REGEXP_ENCODINGS[:none] if node.ascii_8bit?
      return Capi::REGEXP_ENCODINGS[:euc_jp] if node.euc_jp?
      return Capi::REGEXP_ENCODINGS[:windows_31j] if node.windows_31j?
      return Capi::REGEXP_ENCODINGS[:utf_8] if node.utf_8?

      Capi::REGEXP_ENCODINGS[:source]
    end

    # A non-interpolated regexp is one frozen object per site, which the
    # runtime keeps and every evaluation of the literal answers.
    def literal_regexp(node)
      slot = f.slot
      ptr, len = rodata_ref(node.unescaped)
      flag = ->(on) { f.iconst("i8", on ? 1 : 0) }
      status_check(f.val(
        "call #{f.import("zeo_rt_regexp_lit")}(#{f.iconst("i32", @program.regexp_site)}, #{ptr}, #{len}, " \
        "#{flag.call(node.ignore_case?)}, #{flag.call(node.extended?)}, #{flag.call(node.multi_line?)}, " \
        "#{f.iconst("i8", regexp_encoding(node))}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # A bare name searches the cref chain, which inside a class or one of
    # its methods is that class and then Object -- and a miss names the
    # qualified spelling, as ruby's NameError does.
    def constant_named(name, qualified = nil)
      qualified ||= owner == Names::OBJECT ? name : "#{owner}::#{name}"
      ids, n_ids = cid_array(cref_ids)
      nptr, nlen = rodata_ref(name)
      qptr, qlen = rodata_ref(qualified)
      slot = f.slot
      status_check(f.val(
        "call #{f.import("zeo_rt_const_get_cref")}(#{ids}, #{n_ids}, #{nptr}, #{nlen}, #{qptr}, #{qlen}, " \
        "#{f.iconst("i8", 0)}, #{f.iconst("i32", Capi::MAIN_BOX)}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # `A::B`: the scope is lowered as an expression and the leaf read off
    # the value, so a scope ze0 cannot name at compile time still works.
    def constant_path_read(node)
      raise Unsupported.new(node, "a constant path with no scope") if node.parent.nil?

      owner = static_scope(node.parent)
      name = node.name.to_s
      # The guard needs the owner's ID, so a scope ze0 cannot name is
      # refused -- but only for a name some body marks private. Every
      # other read is unguarded because nothing could guard it.
      if owner.nil? && @private_constants.key?(name)
        raise Unsupported.new(node, "a private constant read through a scope this program cannot name")
      end

      scope = lower_expr(node.parent)
      nptr, nlen = rodata_ref(name)
      qptr, qlen = rodata_ref(node.slice)
      private_constant_guard(owner, name, node.slice) if owner
      slot = f.slot
      status_check(f.val(
        "call #{f.import("zeo_rt_const_get_on_value")}(#{borrow(scope)}, #{nptr}, #{nlen}, " \
        "#{qptr}, #{qlen}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # The class a constant path's scope names, when this program declares
    # it. Only then can the read ask whether the constant is private:
    # `zeo_rt_const_private` takes the owner's ID.
    def static_scope(node)
      case node
      when Prism::ConstantReadNode then resolve_class(owner, node.name.to_s)
      when Prism::ConstantPathNode then node.parent && qualify_path(node)
      end
    end

    def qualify_path(node)
      up = static_scope(node.parent)
      up && @classes.key?("#{up}::#{node.name}") ? "#{up}::#{node.name}" : nil
    end

    # `A::B` where B is private raises, and the check is at the READ, not
    # in the lookup -- privacy is positional, so which directive last ran
    # is the run time's answer.
    def private_constant_guard(scope_name, name, path)
      return unless @classes.fetch(scope_name)[:private_constants].include?(name)

      nptr, nlen = rodata_ref(name)
      pptr, plen = rodata_ref(path)
      cid = class_id(scope_name)
      hidden, go = f.label, f.label
      f.ins "brif #{f.val("call #{f.import("zeo_rt_const_private")}(#{cid}, #{nptr}, #{nlen})")}, #{hidden}, #{go}"
      f.switch(hidden)
      status_check(f.val(
        "call #{f.import("zeo_rt_raise_private_constant")}(#{cid}, #{nptr}, #{nlen}, #{pptr}, #{plen})",
      ))
      f.ins "jump #{go}"
      f.switch(go)
    end

    # The table clones the value and stamps the location
    # `Module#const_source_location` reads back.
    def constant_write(node)
      store_constant(node.name.to_s, node, lower_expr(node.value))
    end

    def store_constant(name, node, value)
      at = borrow(value)
      nptr, nlen = rodata_ref(name)
      fptr, flen = rodata_ref(@program.file)
      f.ins "call #{f.import("zeo_rt_const_set_at")}(#{cref_ids.first}, #{nptr}, #{nlen}, " \
            "#{at}, #{fptr}, #{flen}, #{f.iconst("i32", node.location.start_line)}, " \
            "#{f.iconst("i32", Capi::MAIN_BOX)})"
      Operand.new(value.at, false, value.immediate)
    end

    # The cref a bare constant reads through: every enclosing scope,
    # innermost first, and `Object` last.
    def cref_ids
      cref_path.map { |name| class_id(name) } + [f.iconst("i32", Capi::OBJECT_CLASS)]
    end

    def cref_path
      return [] if owner == Names::OBJECT

      parts = owner.split("::")
      parts.size.downto(1).map { |n| parts.first(n).join("::") }
    end

    # A class's id, read out of `zeo_class_ids`. Ids are assigned when the
    # program is linked, so this is the one place ze0 learns one -- the
    # same indirection `zeo_syms` gives an interned symbol.
    def class_id(name)
      base = f.val("symbol_value.i64 #{f.symbol("zeo_class_ids")}")
      at = @program.class_slot(name) * 4
      f.val("load.i32 notrap aligned #{base}#{at.zero? ? "" : "+#{at}"}")
    end

    # A class-id array in a stack slot. The runtime reads it as `*const
    # u32`, and rodata has no alignment to give it.
    def cid_array(ids)
      slot = f.slot([ids.size * 4, Capi::SLOT_BYTES].max)
      ids.each_with_index do |id, i|
        at = i.zero? ? addr_of(slot) : f.stack_addr("#{slot}+#{i * 4}")
        f.ins "store notrap aligned #{id}, #{at}"
      end
      [addr_of(slot), f.iconst("i64", ids.size)]
    end

    # ---- locals ----

    # A fresh local, nil until something writes it. A name a block
    # captures gets a heap cell instead of the slot's own bytes, because
    # the closure outlives this frame and both must see one binding.
    def declare_local(name, boxed: false)
      slot = f.slot
      store_nil(addr_of(slot))
      unless boxed
        return locals[name] = Local.new(slot, nil)
      end

      cell = f.val("call #{f.import("zeo_rt_cell_new")}(#{f.iconst("i64", 0)})")
      f.ins "store notrap aligned #{cell}, #{addr_of(slot)}"
      locals[name] = Local.new(slot, :owned)
    end

    # A cell one of this block's `ProcEnv` rows names. The proc owns it, so
    # this scope only borrows.
    def declare_captured(name, env, index)
      cells = f.val("load.i64 notrap aligned #{env}")
      at = index.zero? ? cells : f.val("iadd.i64 #{cells}, #{f.iconst("i64", index * 8)}")
      slot = f.slot
      f.ins "store notrap aligned #{f.val("load.i64 notrap aligned #{at}")}, #{addr_of(slot)}"
      locals[name] = Local.new(slot, :borrowed)
    end

    # The cell a boxed local's slot points at.
    def cell_of(local)
      f.val("load.i64 notrap aligned #{addr_of(local.slot)}")
    end

    def local_read(node)
      read_local(local(node))
    end

    def read_local(local)
      return Operand.new(local.slot, false, false) unless local.boxed?

      slot = f.slot
      f.ins "call #{f.import("zeo_rt_cell_load")}(#{cell_of(local)}, #{addr_of(slot)})"
      Operand.new(slot, true, false)
    end

    def local_write(node)
      store_local(local(node), lower_expr(node.value))
    end

    # The old value goes after the new one is held, so `x = x` keeps it.
    def store_local(local, value)
      unless local.boxed?
        from = hand_over(value)
        release_if_heap(addr_of(local.slot))
        copy(from, addr_of(local.slot))
        return Operand.new(local.slot, false, false)
      end

      # The cell TAKES the value, so the assignment's own answer is the
      # pooled copy rather than the slot the cell now owns.
      at = borrow(value)
      retain_if_heap(at)
      f.ins "call #{f.import("zeo_rt_cell_store")}(#{cell_of(local)}, #{at})"
      Operand.new(value.at, false, value.immediate)
    end

    # A parameter's value into its local: the caller keeps its own
    # reference, so the copy retains first.
    def initialize_local(local, from)
      retain_if_heap(from)
      if local.boxed?
        f.ins "call #{f.import("zeo_rt_cell_store")}(#{cell_of(local)}, #{from})"
      else
        copy(from, addr_of(local.slot))
      end
    end

    def release_local(local)
      return release_if_heap(addr_of(local.slot)) unless local.boxed?
      return unless local.owns_cell?

      f.ins "call #{f.import("zeo_rt_cell_release")}(#{cell_of(local)})"
    end

    def local(node)
      locals.fetch(node.name) { raise Unsupported.new(node, "the local #{node.name} has no slot") }
    end

    # ---- multiple assignment ----

    # `a, b = 1, 2` and `a, *rest = list`. The runtime does the split --
    # an Array destructures directly and anything else goes through
    # ruby's `to_ary` rule -- and writes one owned value per target slot.
    def multi_write(node)
      splat = rest_target(node.rest)

      targets = node.lefts + (splat ? [splat] : []) + node.rights
      value = lower_expr(node.value)
      slots = f.slot(Capi::SLOT_BYTES * targets.size)
      at = addr_of(slots)
      status_check(f.val(
        "call #{f.import("zeo_rt_multi_split")}(#{borrow(value)}, #{f.iconst("i64", node.lefts.size)}, " \
        "#{f.iconst("i8", splat ? 1 : 0)}, #{f.iconst("i64", node.rights.size)}, #{at})",
      ))
      targets.each_with_index do |target, i|
        from = i.zero? ? at : f.stack_addr("#{slots}+#{i * Capi::SLOT_BYTES}")
        assign_target(target, from)
      end
      # The assignment answers its right-hand side, which the split only
      # read.
      Operand.new(value.at, false, value.immediate)
    end

    # The rest of a multiple assignment, or nil. A trailing comma
    # (`x, = list`) is ruby's "and drop the rest", which is the shape with
    # no rest slot at all.
    def rest_target(node)
      return nil if node.nil? || node.is_a?(Prism::ImplicitRestNode)
      raise Unsupported.new(node, "a rest of that shape") unless node.is_a?(Prism::SplatNode)

      node
    end

    # One split slot into one target. The slot holds an OWNED value, so
    # the target takes it rather than retaining a copy.
    def assign_target(node, from)
      node = node.expression if node.is_a?(Prism::SplatNode)
      # `a, * = list` names nothing, so its slot is simply let go.
      return f.ins("call #{f.import("zeo_rt_release")}(#{from})") if node.nil?

      taken = Operand.new(from, true, false)
      case node
      when Prism::LocalVariableTargetNode then store_local(local(node), taken)
      when Prism::InstanceVariableTargetNode then store_ivar(ivar_key(node.name), taken)
      when Prism::GlobalVariableTargetNode then store_global(node.name.to_s, taken)
      when Prism::ConstantTargetNode then store_constant(node.name.to_s, node, taken)
      when Prism::CallTargetNode
        recv = lower_expr(node.receiver)
        dynamic_send(borrow(recv), node.name, [taken], addr_of(f.slot))
      when Prism::IndexTargetNode
        recv = lower_expr(node.receiver)
        args = (node.arguments&.arguments || []).map { |a| lower_expr(a) }
        dynamic_send(borrow(recv), :[]=, args + [taken], addr_of(f.slot))
      when Prism::MultiTargetNode then multi_target(node, from)
      else raise Unsupported.new(node, "an assignment target of that shape")
      end
    end

    # `(a, b), c = pair, x`: the slot's own value splits again.
    def multi_target(node, from)
      splat = rest_target(node.rest)

      targets = node.lefts + (splat ? [splat] : []) + node.rights
      slots = f.slot(Capi::SLOT_BYTES * targets.size)
      at = addr_of(slots)
      status_check(f.val(
        "call #{f.import("zeo_rt_multi_split")}(#{from}, #{f.iconst("i64", node.lefts.size)}, " \
        "#{f.iconst("i8", splat ? 1 : 0)}, #{f.iconst("i64", node.rights.size)}, #{at})",
      ))
      f.ins "call #{f.import("zeo_rt_release")}(#{from})"
      targets.each_with_index do |target, i|
        assign_target(target, i.zero? ? at : f.stack_addr("#{slots}+#{i * Capi::SLOT_BYTES}"))
      end
    end

    # ---- calls ----

    # The `Module` methods a class body calls to change what the class IS.
    # ze0 registers a class statically, so each of these would answer
    # differently from ruby rather than not at all: `attr_reader :x` left
    # `x` undefined, and `private` left a method public.
    CLASS_MACROS = %i[
      include extend prepend
      module_function define_method
      public_constant private_class_method public_class_method
      undef_method remove_method const_set class_eval module_eval instance_eval
      refine using
    ].freeze

    # The class-body macros the declaration pass has already answered.
    # Nothing is dispatched here: what is left is the VALUE ruby gives the
    # statement, and, for a positional `private :x`, the retag itself --
    # which is a run-time call because a reopen can change it.
    def lower_class_macro(node)
      args = node.arguments&.arguments || []
      name = node.name.to_s
      if name == "private_constant"
        # The class row carries the names; nothing runs here.
        accessor_names(node, args)
        return Operand.new(self_operand.at, false, self_operand.immediate)
      end
      if VISIBILITY.include?(name)
        return literal_nil if args.empty?
        # `private def x` answers the `def`'s own value, and the row the
        # declaration pass wrote already carries the visibility.
        return args.map { |a| lower_expr(a) }.last if args.all?(Prism::DefNode)

        names = accessor_names(node, args)
        verb = f.iconst("i8", Capi::VISIBILITY_VERBS.fetch(name))
        cid = class_id(owner)
        names.each do |n|
          status_check(f.val(
            "call #{f.import("zeo_rt_runtime_set_visibility")}(#{cid}, #{sym_id(n)}, #{verb})",
          ))
        end
        return names.size == 1 ? literal_symbol(names.first) : symbol_array(names)
      end

      return lower_alias(node, args[0], args[1]) if name == "alias_method" && args.size == 2

      kind = ACCESSORS[node.name]
      return nil unless kind

      defined = accessor_names(node, args).flat_map do |n|
        (kind == :writer ? [] : [n]) + (kind == :reader ? [] : ["#{n}="])
      end
      symbol_array(defined)
    end

    # `alias b a` and `alias_method :b, :a` are the same thing at run
    # time: the definee is `self`, which in a class body is the class.
    # The runtime resolves the source, so an alias of a builtin method
    # works exactly as it does for one the program wrote.
    def lower_alias(node, new_name, old_name)
      raise Unsupported.new(node, "an alias outside a class body") unless kind == :class_body

      slot = f.slot
      slf = borrow(self_operand)
      status_check(f.val(
        "call #{f.import("zeo_rt_alias_in_default_definee")}(#{slf}, #{slf}, " \
        "#{borrow(alias_name(new_name))}, #{borrow(alias_name(old_name))}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # The `alias` KEYWORD answers nil, where `alias_method` answers the
    # new name.
    def lower_alias_statement(node)
      discard(lower_alias(node, node.new_name, node.old_name))
      literal_nil
    end

    def alias_name(node)
      case node
      when Prism::SymbolNode then literal_symbol(node.unescaped)
      else raise Unsupported.new(node, "an alias name of that shape")
      end
    end

    def symbol_array(names)
      slot = f.slot
      at = addr_of(slot)
      f.ins "call #{f.import("zeo_rt_array_new")}(#{f.iconst("i64", names.size)}, #{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      names.each { |n| f.ins "call #{f.import("zeo_rt_array_push")}(#{at}, #{hand_over(literal_symbol(n))})" }
      Operand.new(slot, false, false)
    end

    # The verbs that bring another file's statements into the program.
    # ze0 compiles one file, so each would run as an ordinary send and
    # then fail -- or, for `autoload`, answer a constant ruby resolves.
    LOAD_VERBS = %i[require require_relative load autoload].freeze

    def lower_call(node)
      if node.receiver.nil? && kind == :class_body
        raise Unsupported.new(node, "`#{node.name}` in a class body") if CLASS_MACROS.include?(node.name)

        macro = lower_class_macro(node)
        return macro if macro
      end
      if node.receiver.nil? && LOAD_VERBS.include?(node.name)
        raise Unsupported.new(node, "`#{node.name}`")
      end
      return safe_call(node) if safe_navigation?(node)

      args = node.arguments&.arguments || []
      # A trailing `k: v` list is its own channel, not a positional Hash.
      keywords = args.pop if args.last.is_a?(Prism::KeywordHashNode)
      args.each do |a|
        case a
        when Prism::SplatNode, Prism::KeywordHashNode, Prism::BlockArgumentNode
          raise Unsupported.new(a, "an argument of that shape")
        end
      end
      plain = node.block.nil? && keywords.nil?
      if plain && node.receiver.nil? && node.name == :block_given? && args.empty?
        block_given(node)
      elsif keywords.nil? && node.receiver.nil? && (d = visible_def(node.name)) &&
            d[:params].plain? && d[:params].required.size == args.size
        direct_call(node, args, d)
      elsif plain && node.receiver.nil? && node.name == :puts
        kernel_puts(args)
      elsif plain && node.receiver && args.size == 1 && inline_binary?(node.name)
        binary(node.name, lower_expr(node.receiver), lower_expr(args[0]))
      else
        send_call(node, args, keywords)
      end
    end

    # The general send: a receiver, its positional arguments, an optional
    # keyword channel, and an optional block. The block is built LAST --
    # after the receiver, the arguments and the keywords -- because it is
    # MOVED in and nothing between its construction and the call may raise.
    def safe_navigation?(node) = node.call_operator_loc&.slice == "&."

    # `x&.y` answers nil without calling when `x` is nil -- NIL alone, not
    # anything falsy, so `false&.to_s` still answers "false".
    def safe_call(node)
      raise Unsupported.new(node, "a safe navigation write") if node.name.to_s.end_with?("=")

      recv = lower_expr(node.receiver)
      result = f.slot
      store_nil(addr_of(result))
      present = f.val("icmp ne #{tag_of(borrow(recv))}, #{f.iconst("i8", Capi::TAG_NIL)}")
      call, join = f.label, f.label
      f.ins "brif #{present}, #{call}, #{join}"
      f.switch(call)
      args = node.arguments&.arguments || []
      keywords = args.pop if args.last.is_a?(Prism::KeywordHashNode)
      move(send_call(node, args, keywords, recv), addr_of(result))
      f.ins "jump #{join}" unless f.terminated?
      f.switch(join)
      Operand.new(result, true, false)
    end

    def send_call(node, args, keywords, recv = nil)
      builder = block_builder(node, node.receiver.nil? && node.name == :lambda)
      recv ||= node.receiver ? lower_expr(node.receiver) : self_operand
      result = f.slot
      operands = -> { args.map { |a| lower_expr(a) } }
      if builder
        dynamic_send(borrow(recv), node.name, operands.call, addr_of(result),
                     breaks: true, keywords: keywords) { builder.call }
      else
        dynamic_send(borrow(recv), node.name, operands.call, addr_of(result), keywords: keywords)
      end
      Operand.new(result, true, false)
    end

    # How this call's block gets made, or nil when it has none. The
    # function a literal block compiles to is emitted here; only its
    # `Proc` waits for the call.
    # `lambda { }` answers the block it is handed with the lambda bit set,
    # and the bit is not something `Kernel#lambda` can add later: the arity
    # and the strict binding are baked in at creation. Only a plain call
    # can be that `lambda`; a `super` never is.
    def block_builder(node, lambda_shape = false)
      case node.block
      when nil then nil
      when Prism::BlockNode
        body, captures = lower_block(node.block, lambda_shape)
        -> { proc_new(body, captures, node.block, lambda_shape) }
      when Prism::BlockArgumentNode
        expression = node.block.expression
        raise Unsupported.new(node.block, "an anonymous block forward") if expression.nil?

        -> { block_arg_proc(expression) }
      else raise Unsupported.new(node.block, "a block of that shape")
      end
    end

    # The `Proc` the send is handed. Everything a shaped construction would
    # read from a `zeo_proc_shapes` row goes inline instead: `zeo backend`
    # defines that table with no rows, so the shaped entry is unreachable.
    def proc_new(body, captures, node, lambda_shape)
      shape = parse_params(node.parameters&.parameters)
      fn = f.callee(body, ["i64"] * 6, "i32")
      address = f.val("func_addr.i64 #{fn}")
      file, file_len = rodata_ref(@program.file)
      params, n_params = param_rows(shape)
      cells, n_cells = cell_array(captures)
      slot = f.slot
      null = f.iconst("i64", 0)
      lexical = yield_block || f.iconst("i64", 0)
      f.ins "call #{f.import("zeo_rt_proc_new")}(#{address}, #{cells}, #{n_cells}, " \
            "#{borrow(self_operand)}, #{lexical}, #{null}, " \
            "#{f.iconst("i32", proc_arity(shape, lambda_shape))}, " \
            "#{f.iconst("i32", lambda_shape ? Capi::PROC_LAMBDA : 0)}, " \
            "#{params}, #{n_params}, #{file}, #{file_len}, " \
            "#{f.iconst("i32", node.location.start_line)}, #{null}, #{null}, #{addr_of(slot)})"
      addr_of(slot)
    end

    # `Proc#arity`, mirroring `clif/params.rs`'s. A block's arity is
    # NEGATIVE only when a rest can swallow more; a lambda's is negative
    # whenever what it accepts is not exactly what it requires.
    def proc_arity(shape, lambda_shape)
      required = shape.required.size + shape.post.size
      required += 1 if shape.keywords.any?(&:required)
      most = shape.rest.nil? &&
             shape.required.size + shape.optional.size + shape.post.size +
             (shape.keywords.any? || shape.kwrest ? 1 : 0)
      positive = most && (!lambda_shape || required == most)
      positive ? required : -required - 1
    end

    # The cells this block captures, as the `*const *mut Cell` array the
    # proc reads. The proc takes its own reference to each, so this scope
    # keeps releasing its own.
    def cell_array(captures)
      return [f.iconst("i64", 0), f.iconst("i64", 0)] if captures.empty?

      slot = f.slot(8 * captures.size)
      at = addr_of(slot)
      captures.each_with_index do |n, i|
        cell = cell_of(locals.fetch(n))
        off = i * 8
        f.ins "store notrap aligned #{cell}, #{at}#{off.zero? ? "" : "+#{off}"}"
      end
      [at, f.iconst("i64", captures.size)]
    end

    # The `ParamC` rows behind `Proc#parameters`, on the stack. The rows
    # themselves are read during the call, but the NAME bytes they point at
    # are kept, so those come from rodata rather than from a slot.
    PARAM_ROW_BYTES = 24

    def param_rows(shape)
      rows = shape.rows
      return [f.iconst("i64", 0), f.iconst("i64", 0)] if rows.empty?

      slot = f.slot(PARAM_ROW_BYTES * rows.size)
      at = addr_of(slot)
      rows.each_with_index do |row, i|
        kind, name = row
        off = i * PARAM_ROW_BYTES
        ptr, len = rodata_ref(name.to_s)
        # The runtime renders a non-lambda block's `req` as `opt`.
        f.ins "store notrap aligned #{f.iconst("i8", Capi::PARAM_KINDS.index(kind))}, " \
              "#{at}#{off.zero? ? "" : "+#{off}"}"
        f.ins "store notrap aligned #{ptr}, #{at}+#{off + 8}"
        f.ins "store notrap aligned #{len}, #{at}+#{off + 16}"
      end
      [at, f.iconst("i64", rows.size)]
    end

    # `->(x) { }`: a lambda with no send around it.
    def lower_lambda(node)
      body, captures = lower_block(node, true)
      slot = f.slot
      copy(proc_new(body, captures, node, true), addr_of(slot))
      Operand.new(slot, true, false)
    end

    # `&expr`: a Proc passes through, a Symbol becomes its proc, nil means
    # no block, and anything else answers `to_proc`. The send spells "no
    # block" as a null pointer, which is what the nil check is for.
    def block_arg_proc(node)
      value = lower_expr(node)
      slot = f.slot
      at = addr_of(slot)
      status_check(f.val("call #{f.import("zeo_rt_block_arg_to_proc")}(#{borrow(value)}, #{at})"))
      absent = f.val("icmp eq #{tag_of(at)}, #{f.iconst("i8", Capi::TAG_NIL)}")
      f.val("select #{absent}, #{f.iconst("i64", 0)}, #{at}")
    end

    # A call to a `def` this program carries, straight to its body. The
    # block, when there is one, is built LAST and moved in.
    def direct_call(node, args, definition)
      raise Unsupported.new(node.block, "a block for a def that does not use one") if node.block && !definition[:block]

      operands = args.map { |a| lower_expr(a) }
      result = f.slot
      n_params = args.size + (definition[:block] ? 3 : 2)
      body = f.callee(body_symbol_of(definition[:owner], node.name, false), ["i64"] * n_params, "i32")
      addrs = [borrow(self_operand)] + operands.map { |o| borrow(o) }
      if definition[:block]
        addrs << if node.block
                   body_fn, captures = lower_block(node.block)
                   proc_new(body_fn, captures, node.block, false)
                 else
                   f.iconst("i64", 0)
                 end
      end
      status = f.val("call #{body}(#{(addrs + [addr_of(result)]).join(", ")})")
      node.block ? catch_break(status, addr_of(result)) : status_check(status)
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
    def dynamic_send(recv, name, operands, into, breaks: false, keywords: nil)
      argv = args_array(operands)
      kw = keywords ? borrow(hash_literal(keywords)) : nil
      blk = block_given? ? yield : f.iconst("i64", 0)
      sym_id = sym_id(name)
      site = f.val("symbol_value.i64 #{f.symbol("zeo_callsites")}")
      offset = @program.callsite * Capi::CALLSITE_BYTES
      site = f.val("iadd.i64 #{site}, #{f.iconst("i64", offset)}") unless offset.zero?
      entry = kw ? "zeo_rt_send_value_kw_cached" : "zeo_rt_send_value_cached"
      channels = kw ? "#{kw}, #{blk}" : blk.to_s
      status = f.val(
        "call #{f.import(entry)}(#{site}, #{f.iconst("i32", 0)}, #{recv}, #{sym_id}, " \
        "#{argv}, #{f.iconst("i64", operands.size)}, #{channels}, #{into})",
      )
      breaks ? catch_break(status, into) : status_check(status)
    end

    # A send that passed a block lands here: a `Break` signal's value IS
    # the send's value, and every other signal is a real unwind.
    def catch_break(status, into)
      ok, signalled, take = f.label, f.label, f.label
      f.ins "brif #{status}, #{signalled}, #{ok}"
      f.switch(signalled)
      kind = f.val("call #{f.import("zeo_rt_signal_kind")}()")
      f.ins "brif #{f.val("icmp eq #{kind}, #{f.iconst("i8", Capi::SIGNAL_BREAK)}")}, #{take}, #{raise_block}"
      f.switch(take)
      f.val("call #{f.import("zeo_rt_signal_take")}(#{into})")
      f.ins "jump #{ok}"
      f.switch(ok)
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

    def inline_binary?(name)
      INT_ARITH.key?(name) || INT_COMPARE.key?(name)
    end

    # `a OP b` with the Int/Int fast path inline and the send otherwise.
    def binary(name, lhs, rhs)
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
      if (arith = INT_ARITH[name])
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
        answer = f.val("icmp #{INT_COMPARE[name]} #{a}, #{b}")
        f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_BOOL)}, #{out_at}"
        f.ins "store notrap aligned #{answer}, #{out_at}+8"
        f.ins "jump #{join}"
      end
      f.switch(slow)
      dynamic_send(la, name, [Operand.new(rhs.at, false, rhs.immediate)], out_at)
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
      body_statements(statements).each do |s|
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

    # `a && b` and `a || b` answer one of their OPERANDS, not a boolean,
    # so the arm that runs moves its value into the shared slot.
    def and_or(left, right, conjunction)
      value = lower_expr(left)
      truth = truthy(value)
      result = f.slot
      short, other, join = f.label, f.label, f.label
      f.ins "brif #{truth}, #{conjunction ? other : short}, #{conjunction ? short : other}"
      f.switch(short)
      arm(value, result, join)
      f.switch(other)
      arm(lower_expr(right), result, join)
      f.switch(join)
      Operand.new(result, true, false)
    end

    # `case`: each `when` value is tested with `===` against the subject,
    # left to right, and the first hit's body answers. A subjectless
    # `case` tests each value's own truth, ruby's if-chain sugar.
    #
    # Every test runs before any body, so the chain of fall-through blocks
    # stays open until the `else` closes it and no block is left behind
    # without a terminator.
    def lower_case(node)
      subject = nil
      if node.predicate
        subject = lower_expr(node.predicate)
        borrow(subject)
      end
      result = f.slot
      # The `===` answer's scratch byte: a whole slot, of which byte 0 is
      # the only one written.
      hit_at = addr_of(f.slot)
      join = f.label
      bodies = node.conditions.map do |arm_node|
        body = f.label
        arm_node.conditions.each do |value_node|
          hit = case_test(subject, value_node, hit_at)
          fall = f.label
          f.ins "brif #{hit}, #{body}, #{fall}"
          f.switch(fall)
        end
        [body, arm_node.statements]
      end
      # Nothing hit: the `else`, or nil.
      arm(node.else_clause ? lower_statements(node.else_clause.statements) : literal_nil, result, join)
      bodies.each do |body, statements|
        f.switch(body)
        arm(lower_statements(statements), result, join)
      end
      f.switch(join)
      Operand.new(result, true, false)
    end

    def case_test(subject, node, hit_at)
      raise Unsupported.new(node, "a splat in a `when`") if node.is_a?(Prism::SplatNode)

      value = lower_expr(node)

      return truthy(value) unless subject

      at = borrow(value)
      status_check(f.val("call #{f.import("zeo_rt_case_eq")}(#{at}, #{addr_of(subject)}, #{hit_at})"))
      f.val("load.i8 notrap aligned #{hit_at}")
    end

    # `yield` calls the block the caller handed this method. A method with
    # no block raises ruby's LocalJumpError, which the runtime does.
    def lower_yield(node)
      blk = yield_block
      raise Unsupported.new(node, "a yield outside a method that takes a block") if blk.nil?

      args = (node.arguments&.arguments || []).map do |a|
        raise Unsupported.new(a, "a yield argument of that shape") if a.is_a?(Prism::SplatNode)

        lower_expr(a)
      end
      argv = args_array(args)
      slot = f.slot
      status_check(f.val(
        "call #{f.import("zeo_rt_yield")}(#{blk}, #{argv}, #{f.iconst("i64", args.size)}, #{addr_of(slot)})",
      ))
      Operand.new(slot, true, false)
    end

    # `begin ... end`. Without a clause it is a bare grouping and the
    # statements are the whole of it.
    #
    # With one, the body lowers against a landing of its own -- the one
    # piece of state a `begin` swaps -- and every fallible call inside it
    # arrives there. A Raise is taken and matched against the clauses;
    # every other signal is a real unwind and propagates untouched, which
    # is safe because `zeo_rt_signal_take` only consumes the payload of a
    # Raise, Break, Next or Return.
    def lower_begin(node)
      raise Unsupported.new(node.ensure_clause, "an ensure clause") if node.ensure_clause
      return lower_statements(node.statements) if node.rescue_clause.nil?

      outer = scope.raise_block
      landing, done = f.label, f.label
      result = f.slot
      store_nil(addr_of(result))

      scope.raise_block = landing
      value = lower_statements(node.statements)
      value = lower_statements(node.else_clause&.statements) if node.else_clause
      scope.raise_block = outer
      unless f.terminated?
        move(value, addr_of(result))
        f.ins "jump #{done}"
      end

      f.switch(landing)
      lower_rescue_clauses(node.rescue_clause, outer, result, done)
      f.switch(done)
      Operand.new(result, true, false)
    end

    # The begin's landing: take the exception, try each clause in turn,
    # and re-arm the Raise when none matched.
    def lower_rescue_clauses(clause, outer, result, done)
      raised = f.val("icmp eq #{f.val("call #{f.import("zeo_rt_signal_kind")}()")}, #{f.iconst("i8", Capi::SIGNAL_RAISE)}")
      take = f.label
      f.ins "brif #{raised}, #{take}, #{outer}"
      f.switch(take)
      exc = f.slot
      f.val("call #{f.import("zeo_rt_signal_take")}(#{addr_of(exc)})")
      # The pool owns it from here; every use below borrows.
      borrow(Operand.new(exc, true, false))

      while clause
        matched = clause_matches(clause, exc, outer)
        body, nxt = f.label, f.label
        f.ins "brif #{matched}, #{body}, #{nxt}"
        f.switch(body)
        lower_rescue_body(clause, exc, outer, result, done)
        f.switch(nxt)
        clause = clause.subsequent
      end

      # Nothing matched: the pool keeps its own reference, so the signal
      # takes a fresh one before it is re-armed.
      retain_if_heap(addr_of(exc))
      f.ins "call #{f.import("zeo_rt_signal_set")}(#{f.iconst("i8", Capi::SIGNAL_RAISE)}, #{addr_of(exc)})"
      f.ins "jump #{outer}"
    end

    # Whether one clause catches this exception. `rescue` matches with
    # `Module#===`, so the listed classes are ordinary expressions and a
    # bare clause is `StandardError` read like any other constant -- no
    # class id is needed, and a builtin matches the same as a declared one.
    def clause_matches(clause, exc, outer)
      listed = clause.exceptions.map do |e|
        raise Unsupported.new(e, "a splat in a rescue clause") if e.is_a?(Prism::SplatNode)

        lower_expr(e)
      end
      listed = [constant_named("StandardError")] if listed.empty?
      hit = f.slot(1)
      status = f.val(
        "call #{f.import("zeo_rt_rescue_matches_any")}(#{addr_of(exc)}, " \
        "#{super_array(listed)}, #{addr_of(hit)})",
      )
      # A matcher can raise -- an undefined constant, or a listed value
      # that is not a Module -- and that raise leaves this begin.
      cont = f.label
      f.ins "brif #{status}, #{outer}, #{cont}"
      f.switch(cont)
      f.val("load.i8 notrap aligned #{addr_of(hit)}")
    end

    # One clause's body, with `$!` held for its whole run. The pop happens
    # on both exits, and `lower_return` and friends pay what they owe.
    def lower_rescue_body(clause, exc, outer, result, done)
      f.ins "call #{f.import("zeo_rt_handling_push")}(#{addr_of(exc)})"
      scope.handling_depth += 1
      bind_rescue_reference(clause.reference, exc)
      clause_land = f.label
      scope.raise_block = clause_land
      value = lower_statements(clause.statements)
      scope.raise_block = outer
      unless f.terminated?
        move(value, addr_of(result))
        f.ins "call #{f.import("zeo_rt_handling_pop")}()"
        f.ins "jump #{done}"
      end
      scope.handling_depth -= 1
      f.switch(clause_land)
      f.ins "call #{f.import("zeo_rt_handling_pop")}()"
      f.ins "jump #{outer}"
    end

    # `rescue Foo => e` binds the exception, borrowed: the pool owns it.
    def bind_rescue_reference(node, exc)
      case node
      when nil then nil
      when Prism::LocalVariableTargetNode
        store_local(local(node), Operand.new(exc, false, false))
      else raise Unsupported.new(node, "a rescue binding of that shape")
      end
    end

    # The `handling_pop`s a direct jump out of this scope owes. The
    # lexical counter stays put: the pops are per path.
    def pop_handling
      scope.handling_depth.times { f.ins "call #{f.import("zeo_rt_handling_pop")}()" }
    end

    # `super` resumes the MRO walk above the class the `def` was WRITTEN
    # in, never above the receiver's own class. Every class contributes a
    # row per instance method it writes, which the backend derives from
    # the `def`s, and this call walks them.
    #
    # `args` is the written argument list, or nil for a bare `super`,
    # which forwards the method's parameters -- by their CURRENT values,
    # as ruby does, so reassigning one before the call sends the new one.
    def lower_super(node, args)
      definition = scope.definition
      raise Unsupported.new(node, "a super outside a method body") if kind != :body || definition.nil?
      raise Unsupported.new(node, "a super in a class method") if definition[:singleton]
      raise Unsupported.new(node, "a super at the top level") if owner == Names::OBJECT
      raise Unsupported.new(node, "a super in a module") if @classes.fetch(owner)[:kind] == "module"

      operands = args ? args.map { |a| super_argument(a) } : forwarded_arguments(definition[:params])
      into = f.slot
      builder = block_builder(node)
      argv = super_array(operands)
      blk = builder ? builder.call : forwarded_block
      status = f.val(
        "call #{f.import("zeo_rt_send_super_from_args")}(#{borrow(self_operand)}, " \
        "#{class_id(owner)}, #{sym_id(definition[:node].name)}, #{argv}, " \
        "#{f.iconst("i8", 0)}, #{f.iconst("i64", 0)}, #{blk}, #{addr_of(into)})",
      )
      builder ? catch_break(status, addr_of(into)) : status_check(status)
      Operand.new(into, true, false)
    end

    def super_argument(node)
      case node
      when Prism::SplatNode, Prism::KeywordHashNode, Prism::BlockArgumentNode
        raise Unsupported.new(node, "a super argument of that shape")
      else lower_expr(node)
      end
    end

    # A bare `super`'s arguments: the method's own parameters, read back
    # out of their locals in slot order.
    def forwarded_arguments(params)
      unless params.keywords.empty? && params.kwrest.nil? && params.rest.nil?
        raise Unsupported.new(scope.definition[:node], "a bare super forwarding that shape")
      end

      names = params.required + params.optional.map(&:name) + params.post
      names.map { |n| read_local(locals.fetch(n)) }
    end

    # The `super` call's own Array of arguments, which the runtime reads
    # rather than a slot array.
    def super_array(operands)
      slot = f.slot
      at = addr_of(slot)
      f.ins "call #{f.import("zeo_rt_array_new")}(#{f.iconst("i64", operands.size)}, #{at})"
      f.ins "call #{f.import("zeo_rt_pool_push")}(#{at})"
      operands.each { |o| f.ins "call #{f.import("zeo_rt_array_push")}(#{at}, #{hand_over(o)})" }
      at
    end

    # With no block written at the `super`, the method's own goes on. The
    # callee consumes a reference and this frame's epilogue releases its
    # own, so the forward takes a fresh one.
    def forwarded_block
      blk = scope.blk
      return f.iconst("i64", 0) if blk.nil?

      has = f.val("icmp ne #{blk}, #{f.iconst("i64", 0)}")
      yes, no = f.label, f.label
      f.ins "brif #{has}, #{yes}, #{no}"
      f.switch(yes)
      f.ins "call #{f.import("zeo_rt_retain")}(#{blk})"
      f.ins "jump #{no}"
      f.switch(no)
      blk
    end

    # The block a bare `yield` reaches: this scope's own, or -- inside a
    # block -- the enclosing method's, which the proc carried along as its
    # `ProcEnv.lexical_blk`. Read once per function, and only where it is
    # asked for.
    def yield_block
      return scope.blk if scope.blk
      return nil if scope.env.nil?

      scope.lexical_blk ||= f.val("load.i64 notrap aligned #{scope.env}+#{Capi::PROC_ENV_LEXICAL_BLK}")
    end

    # `block_given?` is the block pointer against null -- no call at all.
    def block_given(node)
      blk = yield_block
      raise Unsupported.new(node, "a block_given? outside a method that takes a block") if blk.nil?

      slot = f.slot
      at = addr_of(slot)
      has = f.val("icmp ne #{blk}, #{f.iconst("i64", 0)}")
      f.ins "store notrap aligned #{f.iconst("i8", Capi::TAG_BOOL)}, #{at}"
      f.ins "store notrap aligned #{has}, #{at}+8"
      Operand.new(slot, false, true)
    end

    # `next` is not a signal at all: it is the block's ordinary return,
    # with its value in the out slot.
    def lower_next(node)
      raise Unsupported.new(node, "a next outside a block") unless kind == :block

      move(one_value(node), out)
      pop_handling
      f.ins "jump #{done_block}"
      unreachable
    end

    # `break` arms the Break signal and leaves; the send that passed the
    # block takes the value and answers it.
    def lower_break(node)
      raise Unsupported.new(node, "a break outside a block") unless kind == :block

      value = hand_over(one_value(node))
      f.ins "call #{f.import("zeo_rt_signal_set")}(#{f.iconst("i8", Capi::SIGNAL_BREAK)}, #{value})"
      f.ins "jump #{raise_block}"
      unreachable
    end

    # The single value of a `return`, `next` or `break`, or nil.
    def one_value(node)
      args = node.arguments&.arguments || []
      raise Unsupported.new(node, "#{node.class.name[/\w+(?=Node)/].downcase} of several values") if args.size > 1

      args.empty? ? literal_nil : lower_expr(args[0])
    end

    # Nothing runs after a jump; the slot is never written or read.
    def unreachable
      Operand.new(f.slot, false, true)
    end

    def lower_return(node)
      raise Unsupported.new(node, "a return outside a def") unless kind == :body

      # The value is read BEFORE `$!` unwinds, so `return $!.message`
      # inside a rescue clause answers the one it caught.
      move(one_value(node), out)
      pop_handling
      f.ins "jump #{done_block}"
      unreachable
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

    # An address whose value the callee TAKES. An unowned value is
    # retained first, because whoever held it keeps its own reference.
    def hand_over(value)
      at = addr_of(value)
      retain_if_heap(at) if !value.owned && !value.immediate
      value.owned = false
      at
    end

    # `value` into the slot at `to`, which then owns it.
    def move(value, to)
      copy(hand_over(value), to)
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
