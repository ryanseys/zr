# frozen_string_literal: true

require_relative "../ir"
require_relative "../machine/description"
require_relative "scope"
require_relative "function/expressions"
require_relative "function/definitions"
require_relative "function/call_site"
require_relative "function/loop"
require_relative "function/sends"
require_relative "function/sends/refinements"
require_relative "function/sends/in_place"
require_relative "function/sends/arith"
require_relative "function/control"
require_relative "function/regions"
require_relative "function/params"
require_relative "function/targets"
require_relative "function/defined"
require_relative "function/tracing"
require_relative "function/inline"
require_relative "function/iterators"

module Zr
  class Lower
    # One IR function for one Ruby scope: the toplevel (`kind` :main, no
    # parameters), a method (:def, the method ABI), a class or module body
    # (:class or :module, taking the class and the cref) or a block
    # (:block, taking its Proc, the arguments and a block).
    #
    # Every function keeps a frame record in its frame. It contains the
    # locals, and the slots that a send fills with its receiver and
    # arguments while the next argument is evaluated. So the collector
    # sees every Value that the function keeps across a call. The record
    # refers to its FrameMeta and contains the current line, for
    # backtraces. If a call returns `undef`, an unwind is pending: the
    # function leaves through its landing block and also returns `undef`.
    #
    # A scope that contains a block keeps its locals in an Env cell, in
    # the record's first slot, and the block reads and writes them there.
    # A block gets outer locals through its Proc's env chain.
    class Function
      # @rbs @l: Lower
      # @rbs @name: String
      # @rbs @twin: String?
      # @rbs @twin_of: String?
      # @rbs @locals: Array[Symbol]
      # @rbs @body: untyped
      # @rbs @def: untyped
      # @rbs @kind: Symbol
      # @rbs @direct: bool
      # @rbs @outer: Function | Outer | nil
      # @rbs @frame: Machine::Layout
      # @rbs @task: Machine::Layout
      # @rbs @cref_layout: Machine::Layout
      # @rbs @proc_layout: Machine::Layout
      # @rbs @env_layout: Machine::Layout
      # @rbs @slot_of: Hash[Symbol, Integer]
      # @rbs @captures: Hash[Symbol, Integer]
      # @rbs @writes: Array[Symbol]
      # @rbs @has_env: bool
      # @rbs @raw_block: Symbol?
      # @rbs @sites: Integer
      # @rbs @loops: Array[Loop]
      # @rbs @regions: Array[Regions::Region]
      # @rbs @retries: Array[[String, Integer, Integer]]
      # @rbs @f: IR::Function
      # @rbs @base: Integer
      # @rbs @nvalues: Integer
      # @rbs @sp: Integer
      # @rbs @record: String
      # @rbs @rec: String
      # @rbs @task_addr: String
      # @rbs @prev: String
      # @rbs @meta: String
      # @rbs @line: Integer?
      # @rbs @proc: String
      # @rbs @qnil: String
      # @rbs @self: String
      # @rbs @cref: String
      # @rbs @blk: String
      # @rbs @env: String
      # @rbs @body_label: String?
      # @rbs @attributes: Array[Symbol]?
      # @rbs @bindings: Hash[Symbol, Integer]?
      # @rbs @bound: Array[Symbol]?
      # @rbs @funcalls: Hash[Hir::Send, bool]?
      # @rbs @landing: String?
      # @rbs @inline_scope: Iterators::InlineScope?
      # @rbs @line_rec: String?
      # @rbs @inline: Inline::Site?
      # @rbs @native_operators: bool?
      # @rbs @native_each: bool?

      include Expressions
      include Definitions
      include Sends
      include Control
      include Regions
      include Params
      include Targets
      include Defined
      include Tracing
      include Inline
      include Iterators

      KINDS = { main: "KIND_MAIN", top: "KIND_TOP", def: "KIND_DEF", class: "KIND_CLASS", module: "KIND_MODULE", sclass: "KIND_SCLASS", block: "KIND_BLOCK", eval: "KIND_EVAL" }.freeze #: Hash[Symbol, String]
      # The maximum arguments that a direct entry takes in registers.
      # `direct0` to `direct4` are its ABIs, one for each count
      # (lib/zr/runtime/kernel/class.rb).
      DIRECT_ARGS = 4
      ABI = { main: [], #: Array[String]
              top: [], #: Array[String]
              def: %w[i64 i64 i64 i64 i64 i64], class: %w[i64 i64], module: %w[i64 i64], sclass: %w[i64 i64], block: %w[i64 i64 i64 i64], eval: %w[i64 i64 i64 i64],
              **(0..DIRECT_ARGS).to_h { |n| [:"direct#{n}", Array.new(4 + n, "i64")] } }.freeze #: Hash[Symbol, Array[String]]
      #: (Integer n) -> Symbol
      def self.direct_abi(n) = :"direct#{n}"

      # The `&b` parameter bound to the block as given (a Proc that can
      # still be on the caller's stack), or nil (`Params#raw_block?`).
      attr_reader :meta #: String
      attr_reader :outer #: Function | Outer | nil
      attr_reader :kind #: Symbol
      attr_reader :raw_block #: Symbol?

      # The Def, Block or body node this function came from.
      #: () -> untyped
      def def_node
        @def
      end

      # Whether a def uses the direct ABI (`ABI[:direct]`): only required
      # positionals, four at most, and no pattern. A site that passes that
      # many arguments proves the count, so the def reads them from
      # registers with no keyword word and no count check
      # (lib/zr/runtime/kernel/class.rb, MEntry.direct). A traced program's defs
      # use the generic ABI, because its hooks read every frame the same way.
      #: (Hir::Def node, Lower lower) -> bool
      def self.direct_def?(node, lower)
        p = node.params
        !lower.traced? && p.plain? && p.required.size <= DIRECT_ARGS && p.required.none?(Hir::MultiTarget)
      end

      # A block can have a twin (`Lower#block`): `twin` names it in the
      # block's meta, and the twin itself has `twin_of`, the block's name.
      # The twin takes the method signature from a send of the
      # `define_method` entry. It uses the block's meta and tables, and it
      # makes the frame that `zr_bmethod_fn` and the block make together,
      # with no Proc copy: self is the receiver, the cref is the entry's,
      # and it is always a lambda. It reads the env and the block from the
      # entry's Proc.
      #
      # @rbs lower: Lower
      # @rbs name: String
      # @rbs locals: Array[Symbol]
      # @rbs body: untyped
      # @rbs node: untyped
      # @rbs kind: Symbol
      # @rbs outer: Function | Outer | nil
      # @rbs twin: String?
      # @rbs twin_of: String?
      # @rbs return: void
      def initialize(lower, name, locals, body, node, kind, outer: nil, twin: nil, twin_of: nil)
        @l = lower
        @name = name
        @twin = twin
        @twin_of = twin_of
        @locals = locals
        @body = body
        @def = node
        @kind = kind
        @direct = kind == :def && Function.direct_def?(node, lower)
        @outer = outer
        @frame = lower.layout("Frame")
        @task = lower.layout("Task")
        @cref_layout = lower.layout("RCref")
        @proc_layout = lower.layout("RProc")
        @env_layout = lower.layout("REnv")
        @slot_of = locals.each_with_index.to_h
        lower.spell(locals)
        # This scope's captures (outer locals): the depth of each from
        # here, in the order of first use, and the ones that it writes.
        @captures = {}
        @writes = []
        # A traced program's hooks can read a Binding of any frame, and
        # only an Env gives one.
        @has_env = %i[eval main].include?(@kind) || Hir::Locals.holds_block?(body) || Hir::Locals.opens_locals?(body) ||
                   default_expressions.any? { |d| Hir::Locals.holds_block?(d) || Hir::Locals.opens_locals?(d) } ||
                   (lower.traced? && !lower.internal? && %i[def block top].include?(@kind))
        @raw_block = nil
        @raw_block = raw_block?(node.params) ? node.params.block : nil if %i[def block].include?(@kind)
        @sites = 0
        @loops = []
        @regions = []
        @retries = []
        # Set for real in `lower` and `enter`, once this scope's IR
        # function exists. Nil here fixes this object's ivar order
        # before then, so every instance has the same shape
        # (lib/zr/runtime/kernel/cache.rb, guessed_ivar_row).
        @f = nil
        @base = nil
        @nvalues = nil
        @sp = nil
        @record = nil
        @rec = nil
        @task_addr = nil
        @prev = nil
        @meta = nil
        @line = nil
        @proc = nil
        @qnil = nil
        @self = nil
        @cref = nil
        @blk = nil
        @env = nil
        # `lower`, only for a block: the label its body jumps to, so a
        # `redo` (Control) can jump back to it.
        @body_label = nil
        # Memoized on first use (`attributes`, `bindings`).
        @attributes = nil
        @bindings = nil
        # `Params#bind`, `Params#repeated?`: the parameter names bound so far.
        @bound = nil
        # `Sends#funcall`: the sends that a bare name turned into a funcall.
        @funcalls = nil
        # `Regions#landing`: this scope's own landing block, made on first use.
        @landing = nil
        # `Iterators#loop_in_place`: the inline scope and record of the
        # block body that runs inline, while it runs.
        @inline_scope = nil
        @line_rec = nil
        # `Inline#inline_body`: the `Inline::Site` of the copy that runs
        # at a call site, while it runs.
        @inline = nil
      end

      #: () -> IR::Function
      def lower
        # @type ivar @body_label: String
        abi = if @direct then Function.direct_abi(@def.params.required.size)
              elsif @twin_of then :def
              else @kind
              end
        @f = IR::Function.new(@name, ABI.fetch(abi), "i64")
        enter
        bind_params
        # A method that only recurses has no back edge. So it yields to
        # the scheduler at its entry, after its record contains its
        # arguments.
        preempt if @kind == :def
        trace_open
        cover_method if @kind == :def && method_cover
        if @kind == :block
          @body_label = @f.label
          @f.jump(@body_label)
          switch(@body_label)
        end
        last = expr(@body)
        leave(last) unless @f.terminated?
        land if @landing
        # After the body is lowered, its captures are known, so the
        # captures table that its meta refers to can be written.
        @l.captures_table(@name, capture_rows) unless @twin_of
        @l.functions << @f
        @f
      end

      # The def-site entry that this scope uses when it makes a method, or
      # nil if the program does not measure coverage. A block also has
      # one, because `define_method` makes a method from a block, and ruby
      # gives that method the block's location.
      #: () -> untyped
      def method_cover = %i[def block].include?(@kind) ? @def&.cover : nil

      # The record slot of the local in `node`, `node.depth` scopes up.
      #: (untyped node) -> Integer
      def slot_at(node)
        scope_at(node.depth).slot_index(node)
      end

      # A def's entry, block and found node, at their ABI positions.
      #: () -> String
      def arg_entry = @f.args[@direct ? 1 : 3]
      #: () -> String
      def arg_blk = @f.args[@direct ? 2 : 4]
      #: () -> String
      def arg_found = @f.args[@direct ? 3 : 5]

      # The function `depth` block scopes out from this one.
      #: (Integer depth) -> (Function | Iterators::InlineScope | Outer)
      def scope_at(depth)
        # Read only after the test that it is set:
        # @type ivar @inline_scope: Iterators::InlineScope
        fn = self #: Function | Outer
        # A block body that runs inline (`Iterators`): its own scope is
        # first, and this one is a level out.
        if @inline_scope
          return @inline_scope if depth.zero?

          depth -= 1
        end
        depth.times do
          fn = fn.outer #: Function | Outer
        end
        fn
      end

      # The data object the meta emitted for this scope's local names.
      #: () -> String
      def locals_table = "zr_locals_#{@twin_of || @name}"

      # The block that a block function's call gives it.
      #: () -> String
      def call_block = @twin_of ? arg_blk : @f.args[3]

      #: (untyped node) -> Integer
      def slot_index(node)
        @slot_of.fetch(node.name) { @l.refuse(node, "#{node.name} is not a local of this scope") }
      end

      private

      # The program's toplevel gives its file to the runtime for `$0`.
      #: () -> void
      def program_start
        file = @f.symbol_value(@f.symbol(@l.file_bytes))
        kernel("zr_program_start", file, imm(@l.shown_file.bytesize))
      end

      # The file's parse-time warnings, on stderr as the file starts.
      #: () -> void
      def parse_warnings
        @l.warnings.each do |line|
          text = "#{line}\n"
          kernel("zr_write_err", @f.symbol_value(@f.symbol(@l.literal(text))), imm(text.bytesize))
        end
      end

      # A core def starts with its `Primitive.attr!` attributes. `:hidden`
      # marks a helper that has no CRuby method; it has no backtrace
      # entry. `:ruby` marks a method that CRuby writes in Ruby; it returns
      # its own parameters as CRuby's does. `:frameless` marks a method
      # that ruby runs as an instruction: it is listed as any method is,
      # and has no backtrace entry.
      #: () -> Array[Symbol]
      def attributes
        return [] unless @l.internal? && @kind == :def

        @attributes ||= begin
          # For a def with a `rescue` or `ensure`, read its protected body.
          body = @body.is_a?(Hir::Begin) ? @body.body : @body
          stmts = body.is_a?(Hir::Seq) ? body.stmts : [body]
          stmts.take_while { |stmt| attribute_row?(stmt) }.map { |stmt| stmt.args.first.value }
        end
      end
      protected :attributes

      #: (untyped node) -> bool
      def attribute_row?(node)
        node.is_a?(Hir::Send) && node.name == :attr! && node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Primitive &&
          node.args.first.is_a?(Hir::Literal)
      end

      #: () -> bool
      def hidden_def? = attributes.include?(:hidden)

      # A core def that matches for its own work keeps its matches in its
      # own `$~`, so the program's `$~` is left alone, as a C function's
      # matches leave it: one marked `Primitive.attr! :own_backref`, or one
      # with a regexp literal that neither sets nor reads the caller's `$~`
      # or `$_` itself (those are the methods that ruby defines to set them).
      # An extension's def also owns them when it matches by a call (Date's
      # parsers match with Regexps that constants hold).
      #: () -> bool
      def owns_backref?
        return false unless @l.internal? && @kind == :def
        return true if attributes.include?(:own_backref)

        matches?(@body) == :own
      end

      BACKREF_PRIMITIVES = %i[zr_backref_set zr_backref_get zr_lastline_set zr_lastline_get].freeze #: Array[Symbol]
      MATCH_SENDS = %i[match =~ !~ scan sub gsub sub! gsub! partition rpartition].freeze #: Array[Symbol]

      # :own when `node` matches for its own work (a regexp literal, or in an
      # extension a matching call), :caller when it sets or reads the
      # caller's `$~` or `$_`, else nil. :caller wins.
      #: (untyped node) -> Symbol?
      def matches?(node)
        found = nil
        case node
        when Hir::RegexpLit then found = :own
        when Hir::BackRef then return :caller
        when Hir::GvarRead then return :caller if %i[$~ $_].include?(node.name)
        when Hir::Send
          return :caller if node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Primitive && BACKREF_PRIMITIVES.include?(node.name)

          found = :own if @l.extension? && MATCH_SENDS.include?(node.name)
        end
        Hir.each_child(node) do |child|
          next unless Hir.node?(child) || child.is_a?(Array)

          inner = matches?(child)
          return :caller if inner == :caller

          found ||= inner
        end
        found
      end

      # The stored name of the instance variable `name`. The ivars of the
      # runtime, the core library and the extensions are hidden: their
      # names have no `@`, as for CRuby's C fields, so a program cannot
      # see them. A def marked `:ivars` keeps visible names for the ivars
      # that CRuby writes in Ruby. Prism's and openssl's ports do the same
      # (VISIBLE_IVARS).
      #: (Symbol name) -> Symbol
      def ivar_name(name)
        return name unless @l.internal?
        return name if Hir::VISIBLE_IVARS.include?(@l.file)

        fn = self
        fn = fn.outer while fn.kind == :block && fn.outer
        fn.attributes.include?(:ivars) ? name : name.to_s.delete_prefix("@").to_sym
      end

      # The prologue: the stack check, then link the record into the
      # task's chain, fill its header, set the slots to nil, and make the
      # Env if a block needs one.
      #: () -> void
      def enter
        # @type ivar @line: Integer
        @base = if stack_env? then 1 + @locals.size
                elsif @has_env then 1
                else @locals.size
                end
        @nvalues = @base + [Scope.staging(@body), *default_expressions.map { |e| Scope.staging(e) }].max + prologue_slots
        @sp = @base
        @record = @f.slot(@frame.size + (8 * @nvalues))
        @rec = @f.stack_addr(@record)
        @task_addr = @f.fetch("i64", static("current_task"), 0)
        # A method gets its own entry and the chain node where it was
        # found (`Machine.sig :method`). Its name and cref come from the
        # entry. Both go into the record before the stack check, so no
        # register keeps them across it.
        if @kind == :def
          @f.store(arg_entry, @rec, off(@frame, "entry"))
          @f.store(arg_found, @rec, off(@frame, "defined"))
          cref = entry_field("cref")
        end
        stack_check
        @prev = @f.fetch("i64", @task_addr, off(@task, "top"))
        @f.store(@prev, @rec, off(@frame, "prev"))
        line = @def ? @def.line : 1
        name = @def && %i[class module].include?(@kind) ? @def.name : 0
        params = @def.params if %i[def block].include?(@kind)
        kind = hidden_def? ? "KIND_HIDDEN" : @l.frame_kind(@kind)
        node_id = @def ? @l.node_id(@def) : 0
        @meta = if @twin_of
                  "zr_meta_#{@twin_of}"
                else
                  @l.meta(@name, kind, line, name: name, parent: @outer&.meta, params: params, locals: @locals,
                                             env: @has_env, ruby: attributes.include?(:ruby),
                                             captures: true, node: node_id, cover: method_cover, twin: @twin,
                                             owns_backref: owns_backref?, frameless: attributes.include?(:frameless))
                end
        @f.store(@f.symbol_value(@f.symbol(@meta)), @rec, off(@frame, "meta"))
        @line = line | (node_id << 32)
        @f.store(imm(@line), @rec, off(@frame, "line"))
        @proc = @twin_of ? entry_field("cref") : @f.args[0] if @kind == :block
        @qnil = imm(@l.const("QNIL"))
        @self = case @kind
                when :main, :top then global("G_MAIN")
                when :block then @twin_of ? @f.args[0] : proc_field("self")
                else @f.args[0]
                end
        @cref = case @kind
                when :main, :top then global("G_TOP_CREF")
                when :def then cref
                when :block then @twin_of ? twin_cref : proc_field("cref")
                else @f.args[1]
                end
        # An eval's block is the block of its calling scope, so a `yield`
        # in the string calls the caller's block.
        @blk = case @kind
               when :def then arg_blk
               when :block then proc_field("blk")
               when :eval then @f.args[3]
               else @qnil
               end
        @f.store(@self, @rec, off(@frame, "self"))
        @f.store(@cref, @rec, off(@frame, "cref"))
        @f.store(@blk, @rec, off(@frame, "blk"))
        # A block's frame keeps its call's block in `defined` (a def's
        # frame keeps the node where it was found). A `define_method` body
        # finds there the block that a `break` leaves through.
        unless @kind == :def
          @f.store(imm(0), @rec, off(@frame, "entry"))
          @f.store(@kind == :block ? call_block : @qnil, @rec, off(@frame, "defined"))
        end
        # The serial is set when something first needs it
        # (`zr_frame_serial`). `$~` and `$_` are made at their first write.
        @f.store(imm(0), @rec, off(@frame, "serial"))
        @f.store(imm(@nvalues), @rec, off(@frame, "nvalues"))
        @f.store(@qnil, @rec, off(@frame, "svars"))
        # An active refinement belongs to the call site, not to the callee.
        # So a new ruby frame starts with none.
        @f.store(@qnil, @task_addr, off(@task, "refine"), region: :task)
        program_start if @kind == :main && !@l.internal?
        parse_warnings if %i[main top eval].include?(@kind) && !@l.internal?
        # A required parameter's slot gets the argument directly from argv
        # after the arity check (`bind_method`). Nothing between can start
        # a collection, so the slot needs no nil first.
        skip = direct_params.map { |name| slot_of(name) }
        (0...@nvalues).each { |i| @f.store(@qnil, @rec, value_offset(i)) unless skip.include?(i) }
        @f.store(@rec, @task_addr, off(@task, "top"))
        return unless @has_env

        parent = @kind == :block ? proc_field("env") : @qnil
        @env = if @kind == :eval then @f.args[2]
               elsif stack_env? then env_image(parent)
               else kernel("zr_env_new", parent, imm(@locals.size), @f.symbol_value(@f.symbol(locals_table)))
               end
        @f.store(@env, @rec, value_offset(0))
        kernel("zr_toplevel_binding", @env, @self, @cref, @f.symbol_value(@f.symbol(@meta))) if @kind == :main && !@l.internal?
      end

      # A method's or a block's Env starts in its record: an REnv image
      # whose slots are the record's local slots (1 up to the count). It
      # has the stack flag and is already marked, so the collector reads
      # nothing through it. The first object that keeps the scope moves it
      # to a cell (`zr_env_escape`, lib/zr/runtime/kernel/proc.rb) and points the
      # image's `slots` to the cell's slots. Every read and write loads
      # `slots` first.
      #: () -> bool
      def stack_env? = @has_env && %i[def block].include?(@kind)

      #: (String parent) -> String
      def env_image(parent)
        env = @f.stack_addr(@f.slot(@env_layout.size))
        basic = @l.layout("RBasic")
        @f.store(imm(%w[T_ENV FL_ALLOCATED FL_STACK].sum { |c| @l.const(c) }), env, off(basic, "flags"))
        @f.store(@qnil, env, off(basic, "klass"))
        fields = {
          "parent" => parent, "slots" => @f.iadd(@rec, imm(value_offset(1))), "nslots" => imm(@locals.size),
          "names" => @f.symbol_value(@f.symbol(locals_table)), "cell" => @qnil, "home" => @rec
        }
        fields.each { |name, v| @f.store(v, env, off(@env_layout, name)) }
        env
      end

      # Raises SystemStackError if the record is below the task's stack
      # limit. Nothing is linked yet, so the function returns at once.
      #: () -> void
      def stack_check
        limit = @f.fetch("i64", @task_addr, off(@task, "stack_limit"))
        over = @f.cold(@f.label)
        ok = @f.label
        @f.brif(@f.icmp("ult", @rec, limit), over, ok)
        switch(over)
        @f.ret(kernel("zr_stack_overflow"))
        switch(ok)
      end

      # The landing block: a pending unwind leaves the function, unless
      # it is a `return` from a block of this method. Then this function
      # returns its value.
      #: () -> void
      def land
        # `lower` calls this only when the landing block exists:
        # @type ivar @landing: String
        switch(@landing, open: true)
        # A block frame also catches one: an unwind whose home is this
        # frame belongs to it. This occurs when the block is a lambda and
        # a block inside it returned.
        if %i[def main top eval block].include?(@kind) && @has_env
          take(kernel("zr_catch_return", @rec))
        end
        # A `return` in an eval straight in a file's toplevel ends the file.
        take(kernel("zr_catch_return_here")) if (@kind == :def && @def&.evals) || %i[main top].include?(@kind)
        leave(qundef, unwinding: true)
      end

      # Returns the value if the catch that the landing block just ran
      # took the unwind. Otherwise the landing block continues.
      #: (String caught) -> void
      def take(caught)
        done = @f.label
        none = @f.label
        @f.brif(@f.icmp("eq", caught, qundef), none, done)
        switch(done)
        leave(caught)
        switch(none)
      end

      # A parameter's default runs in the prologue, and stages as the body does.
      #: () -> Array[untyped]
      def default_expressions
        return [] unless %i[def block].include?(@kind)

        p = @def.params
        p.optional.map(&:last) + p.keywords.filter_map(&:last)
      end

      # The record slots for the prologue: one for a method's keyword
      # Hash, one for the Array that a block spreads over its parameters,
      # and one for each level of a destructuring parameter.
      #: () -> Integer
      def prologue_slots
        return 0 unless %i[def block].include?(@kind)

        p = @def.params
        nested = (p.required + p.post).grep(Hir::MultiTarget).map { |t| Scope.targets(t) }.max || 0
        spread = @kind == :block && p.spread? ? 1 : 0
        (keywords?(p) ? 1 : 0) + spread + nested
      end

      # The scope returns `value`. It fires its closing event first,
      # unless it never opened (an arity error leaves before the event).
      #: (String value, ?unwinding: bool, ?opened: bool, ?line: Integer?) -> void
      def leave(value, unwinding: false, opened: true, line: nil)
        value = trace_close(value, unwinding, line) if opened
        @f.store(@prev, @task_addr, off(@task, "top"), region: :task)
        @f.ret(value)
      end

      # A call's result, after the test for a pending unwind: `undef`
      # goes to the landing block.
      #: (String value) -> String
      def checked(value)
        go = @f.label
        @f.brif(@f.icmp("eq", value, qundef), landing, go)
        switch(go)
        value
      end

      # Continue in `block`. The record's line is unknown again, because
      # more than one path can arrive.
      #: (String block, ?open: bool) -> void
      def switch(block, open: false)
        @f.switch(block, open: open)
        @line = nil
      end

      # The line a backtrace reports for what runs next.
      #: (Integer line, ?Integer node_id) -> void
      def at_line(line, node_id = 0)
        # An inlined body's lines are its def's, and nothing in a copy
        # raises or polls. So the record keeps the caller's line.
        return if @inline

        word = line | (node_id << 32)
        return if word == @line

        @line = word
        @f.store(imm(word), @line_rec || @rec, off(@frame, "line"))
      end

      # The same for `node`, with the id of the prism node it came from in
      # the word's high half, which node_id_for_backtrace_location reads.
      #: (untyped node) -> void
      def at_node(node)
        at_line(node.line, @l.node_id(node))
      end

      # The address of the kernel's static word `name`, found once per
      # function.
      #: (String name) -> String
      def static(name)
        @f.symbol_addr(@f.symbol("zr_static_#{name}"))
      end

      # The address of a new cell for one site's cache: `count` of the
      # kernel's `layout` (lib/zr/runtime/kernel/cache.rb).
      #: (String prefix, String layout, ?Integer count) -> String
      def cache(prefix, layout, count = 1)
        @f.symbol_value(@f.symbol(@l.cache_cell(prefix, @l.layout(layout).size * count)))
      end

      # The same for the site `node`, with one cell however many times the
      # node is lowered. Its def's function and every inlined copy
      # (`Inline`) share it.
      #: (untyped node, String prefix, String layout, ?Integer count) -> String
      def site_cache(node, prefix, layout, count = 1)
        @f.symbol_value(@f.symbol(@l.site_cell(node, prefix, @l.layout(layout).size * count)))
      end

      # `@name` and `@name = v` at their sites. The site's cell `ic`
      # guesses the entry in self's ivar table. If the guess contains `id`,
      # this returns the entry in a new block. Else it branches to `slow`,
      # the kernel's read or write, which sets the guess
      # (lib/zr/runtime/kernel/cache.rb). The inline path accepts a plain object,
      # class or module while no ractor has started (GATE_RACTOR; the
      # kernel applies the ractor isolation rule), and not frozen when
      # `writing`.
      #: (String ic, Symbol ivar, String slow, writing: bool) ?{ (String, String) -> void } -> String
      def guessed_ivar_row(ic, ivar, slow, writing:)
        table = @l.layout("IvTab")
        entry = @l.layout("IvEntry")
        plain = @f.label
        indexed = @f.label
        hit = @f.label
        pointer = @f.band(@f.icmp("eq", @f.band(@self, imm(7)), imm(0)), @f.icmp("ugt", @self, @qnil))
        @f.brif(@f.band(pointer, gate_test(["GATE_RACTOR"])), plain, slow)
        switch(plain)
        t = own_ivar_table(slow, writing)
        i = @f.fetch("i64", ic, off(@l.layout("IvarCache"), "index"))
        len = @f.fetch("i64", t, off(table, "len"))
        if block_given?
          # A write whose guess is the entry after the last one of a plain
          # object's table, with a free entry: the first assignment in an
          # `initialize`. The block appends it if the table's names show
          # that no entry contains the name (a site that two classes share
          # can guess past the end of a table that contains it).
          past = @f.label
          room = @f.label
          append = @f.label
          @f.brif(@f.icmp("ult", i, len), indexed, past)
          switch(past)
          in_cell = @f.icmp("eq", t, @f.iadd(@self, imm(off(@l.layout("RObject"), "iv"))))
          @f.brif(@f.band(@f.icmp("eq", i, len), in_cell), room, slow)
          switch(room)
          spare = @f.icmp("ult", len, @f.fetch("i64", t, off(table, "cap")))
          unnamed = @f.icmp("eq", @f.band(@f.fetch("i64", t, off(table, "names")), sym_bit(ivar)), imm(0))
          @f.brif(@f.band(spare, unnamed), append, slow)
          switch(append)
          yield t, len
        else
          @f.brif(@f.icmp("ult", i, len), indexed, slow)
        end
        switch(indexed)
        row = @f.iadd(@f.fetch("i64", t, off(table, "rows")), @f.ishl(i, imm(Math.log2(entry.size).to_i)))
        @f.brif(@f.icmp("eq", @f.fetch("i64", row, off(entry, "id")), sym_word(ivar)), hit, slow)
        switch(hit)
        row
      end

      # The collector's write barrier, for a site that stored `v` into
      # `owner` without the kernel: an entry of self's ivar table, or an
      # element of an Array.
      #
      # A minor collection starts from the roots and the remembered set,
      # and stops at each object that is already marked. So an old object
      # that gets a reference to a young one must be remembered, or the
      # young one is swept while still in use.
      #
      # This emits the fast half of `zr_write_barrier`: self is old, and
      # `v` is a cell, not an immediate. The kernel's function does the
      # rest, only when both are true. A store of a Fixnum, nil, true,
      # false or a Symbol never gets there.
      #
      # `owner` is a cell in an arena, so its address gives the location
      # of its age bit. For an ivar, `owner` is self: a plain object, a
      # class or a module (`own_ivar_table` sends all other kinds, and a
      # Proc or Env on the machine stack, to the kernel). For an element,
      # it is the receiver, which the site already found to be an Array.
      #: (String owner, String v) -> void
      def cell_barrier(owner, v)
        return if immediate?(v)

        head = @l.layout("ArenaHead")
        marks = @l.const("MARK_BYTES")
        arena = @f.band(owner, imm(~(@l.const("ARENA_BYTES") - 1)))
        first = @f.iadd(arena, imm(@l.const("ARENA_HEAD") + (marks * @l.const("ARENA_MAPS"))))
        index = @f.ushr(@f.isub(owner, first), @f.fetch("i64", arena, off(head, "shift")))
        at = @f.iadd(@f.iadd(arena, imm(@l.const("ARENA_HEAD") + marks)), @f.ishl(@f.ushr(index, imm(6)), imm(3)))
        aged = @f.icmp("ne", @f.band(@f.fetch("i64", at, 0), @f.ishl(imm(1), @f.band(index, imm(63)))), imm(0))
        cell = @f.band(@f.icmp("eq", @f.band(v, imm(7)), imm(0)), @f.icmp("ugt", v, @qnil))
        remember = @f.label
        done = @f.label
        @f.brif(@f.band(aged, cell), remember, done)
        switch(remember)
        kernel("zr_write_barrier", owner, v)
        @f.jump(done)
        switch(done)
      end

      #: (String v) -> void
      def ivar_barrier(v) = cell_barrier(@self, v)

      # Whether the compiler knows that `v` is an immediate, so the
      # barrier's test fails. Most values that a program stores into a
      # local, an ivar or an Array are literals, and every such literal
      # goes through `imm`: a Fixnum, a flonum, a Symbol, nil, true and
      # false.
      #: (String v) -> bool
      def immediate?(v)
        word = @f.iconst_of(v)
        !word.nil? && @l.immediate?(word)
      end

      # Self's own ivar table: in its cell for a plain object, in its
      # extension for a class or module. Branches to `slow` for all other
      # kinds, or for a frozen object when `writing`.
      #: (String slow, bool writing) -> String
      def own_ivar_table(slow, writing)
        object = @f.label
        other = @f.label
        classy = @f.label
        found, (t,) = @f.block(["i64"]) #: [String, [String]]
        mask = @l.const("T_MASK") | (writing ? @l.const("FL_FREEZE") : 0)
        kind = @f.band(@f.fetch("i64", @self, off(@l.layout("RBasic"), "flags")), imm(mask))
        @f.brif(@f.icmp("eq", kind, imm(@l.const("T_OBJECT"))), object, other)
        switch(object)
        @f.jump(found, [@f.iadd(@self, imm(off(@l.layout("RObject"), "iv")))])
        switch(other)
        @f.brif(@f.bor(@f.icmp("eq", kind, imm(@l.const("T_CLASS"))), @f.icmp("eq", kind, imm(@l.const("T_MODULE")))), classy, slow)
        switch(classy)
        ext = @f.fetch("i64", @self, off(@l.layout("RClass"), "ext"))
        @f.jump(found, [@f.iadd(ext, imm(off(@l.layout("ClassExt"), "iv")))])
        switch(found)
        t
      end

      # The Env `depth` scopes up: this scope's own, or one from the
      # Proc's chain, walked inline with one load for each parent.
      #: (Integer depth) -> String
      def env_at(depth)
        env, up = @has_env ? [@env, depth] : [proc_field("env"), depth - 1]
        up.times { env = @f.fetch("i64", env, off(@env_layout, "parent")) }
        env
      end

      # Slot `i` of the Env `depth` scopes up: a load of the slots and a
      # load or store at the slot, inline. Every local of a scope that
      # contains a block is there (lib/zr/runtime/kernel/proc.rb).
      # Untyped: Steep cannot type a splat of a tuple.
      #: (Integer i, Integer depth) -> untyped
      def env_slot(i, depth)
        [@f.fetch("i64", env_at(depth), off(@env_layout, "slots")), 8 * i]
      end

      #: (Integer i, Integer depth, ?Symbol? name) -> String
      def read_local(i, depth, name = nil)
        if @inline_scope
          return @f.fetch("i64", @rec, value_offset(i)) if depth.zero?

          depth -= 1
        end
        capture(name, depth, write: false)
        return @f.fetch("i64", @rec, value_offset(i)) if depth.zero? && !@has_env

        @f.fetch("i64", *env_slot(i, depth))
      end

      #: (Integer i, Integer depth, String v, ?Symbol? name) -> String
      def write_local(i, depth, v, name = nil)
        if @inline_scope
          if depth.zero?
            @f.store(v, @rec, value_offset(i))
            return v
          end
          depth -= 1
        end
        capture(name, depth, write: true)
        if depth.zero? && !@has_env
          @f.store(v, @rec, value_offset(i))
        else
          env = env_at(depth)
          @f.store(v, @f.fetch("i64", env, off(@env_layout, "slots")), 8 * i)
          env_barrier(env, v)
        end
        v
      end

      # The collector's write barrier, for a scope that wrote an outer
      # local. An Env that escaped to the heap lives longer than its frame,
      # so a store into its slots is a store into a cell. An Env still on
      # the machine stack has its slots in the frame, which each collection
      # reads as a root. The kernel's barrier skips it by its FL_STACK.
      #
      # Use `zr_env_barrier`, not `zr_write_barrier`: `env` here is the
      # frame's image if the scope has one, and after the scope escapes,
      # the image's slots are the cell's. The barrier must get the cell.
      #
      # This emits the test that `v` is a cell, not an immediate. A store
      # of a Fixnum, nil, true, false or a Symbol fails it. The kernel's
      # function does the rest.
      #: (String env, String v) -> void
      def env_barrier(env, v)
        return if immediate?(v)

        remember = @f.label
        done = @f.label
        @f.brif(@f.band(@f.icmp("eq", @f.band(v, imm(7)), imm(0)), @f.icmp("ugt", v, @qnil)), remember, done)
        switch(remember)
        kernel("zr_env_barrier", env, v)
        @f.jump(done)
        switch(done)
      end

      # Records a capture: a local of an outer scope that this scope reads
      # or writes. A Ractor refuses a block with captures and gives their
      # names, so every scope between the two records it (a block can see
      # past the block that contains it).
      #: (Symbol? name, Integer depth, write: bool) -> void
      def capture(name, depth, write:)
        return if name.nil? || depth.zero?

        @captures[name] ||= depth
        @writes << name if write && !@writes.include?(name)
        @outer&.__send__(:capture, name, depth - 1, write: write)
      end

      # `[name, written, rebound]` for each capture of this scope: whether
      # it writes the local, and whether the owner scope binds it more
      # than once. `Ractor.shareable_proc` refuses a block for either.
      #: () -> Array[[Symbol, bool, bool]]
      def capture_rows
        @captures.map do |name, depth|
          home = self
          depth.times { home = home.outer }
          [name, @writes.include?(name), home.bindings[name] > 1]
        end
      end

      # The binding count of each local of this scope: one for a parameter,
      # and one for each assignment to it here or in an inner block, however
      # often it runs. Ruby counts a local that "may be reassigned" this
      # way: `x = 1` in a loop is one binding, `x = 1; x = 2` is two.
      #: () -> Hash[Symbol, Integer]
      def bindings
        @bindings ||= begin
          counts = Hir::Locals.assignments(@body)
          params = %i[def block].include?(@kind) ? @def.params : nil #: Hir::Params?
          params&.names&.each { |name| counts[name] += 1 }
          counts
        end
      end
      protected :bindings

      # Evaluates `nodes` into new record slots, and reserves `extra` more
      # after them. The block gets the address and index of the first slot.
      # The slots are free again after the block. `evaluate` lowers a node
      # when `expr` is not correct for this caller: string interpolation
      # uses shared frozen Strings for its literal parts, because the
      # program never gets them.
      # `evaluate` is a Proc or a Method, which Steep cannot call as one type.
      #: [T] (Array[untyped] nodes, ?Integer extra, ?evaluate: untyped) { (String, Integer) -> T } -> T
      def staged(nodes, extra = 0, evaluate: nil)
        base = reserve(nodes.size + extra)
        nodes.each_with_index { |n, i| @f.store(evaluate ? evaluate.call(n) : expr(n), @rec, value_offset(base + i)) }
        result = yield(@f.iadd(@rec, imm(value_offset(base))), base)
        release(base)
        result
      end

      # Frees the slots from `base` up, and clears them so the collector
      # keeps nothing alive through them.
      #: (Integer base) -> void
      def release(base)
        (base...@sp).each { |i| @f.store(@qnil, @rec, value_offset(i)) } unless @f.terminated?
        @sp = base
      end

      # A call into the kernel, typed from the def's own signature. The
      # result is the call's value, or nil for a def with no result: the
      # kernel description decides, so the type is untyped.
      #: (String name, *String args) -> untyped
      def kernel(name, *args)
        d = @l.kernel_def(name)
        # A parameter is never Void, so its IR type is never nil.
        params = d.params.map do |_, type|
          Machine::TYPES.fetch(type) #: String
        end
        ret = Machine::TYPES.fetch(d.ret)
        raise ArgumentError, "#{name} takes #{params.size} arguments, not #{args.size}" if params.size != args.size

        fn = @f.callee(name, params, ret, effects: d.effects || IR::Effects::ALL)
        ret ? @f.call_val(fn, args) : @f.call(fn, args)
      end

      #: (Integer n) -> String
      def imm(n)
        @f.iconst("i64", n)
      end

      #: () -> String
      def qundef
        imm(@l.const("QUNDEF"))
      end

      # The program's id for `name`, as a value. A fixed id (a name that
      # the runtime already uses) is an immediate. Every other name is a
      # word in this unit's pool that the link fills, so the unit's code
      # does not depend on the compile order.
      #: (Symbol name) -> String
      def sym_word(name) = pooled(:symid, name) { |id| imm(id) }

      # `name` as a Symbol Value.
      #: (Symbol name) -> String
      def sym_value(name) = pooled(:symval, name) { |id| imm(Lower.symbol_value(id, @l.const("SYMBOL_TAG"))) }

      # The bit in an ivar table's `names` for `name`
      # (lib/zr/runtime/kernel/object.rb, zr_ivtab_name_bit).
      #: (Symbol name) -> String
      def sym_bit(name) = pooled(:symbit, name) { |id| imm(Lower.ivar_name_bit(id)) }

      # This literal site's slot in the run-time table of literal objects.
      # It is a word that the link numbers, as for a symbol id, so a unit
      # contains no counter that the whole program shares.
      #: () -> String
      def site_word
        row = @l.pool_site or return imm(@l.literal_index)

        @f.hoisted_fetch("i64", @f.symbol_addr(@f.symbol(row.first)), row.last)
      end

      #: (Symbol kind, Symbol name) { (Integer) -> String } -> String
      def pooled(kind, name)
        id = @l.fixed_id(name)
        return yield(id) if id

        data, at = @l.pool_word(kind, name)
        @f.hoisted_fetch("i64", @f.symbol_addr(@f.symbol(data)), at)
      end

      #: (String name) -> String
      def proc_field(name)
        @f.fetch("i64", @proc, off(@proc_layout, name))
      end

      # This frame's serial, set now if it has none. A block descriptor
      # contains it, so a later frame at the same address is different
      # from this one (`zr_frame_live`).
      #: () -> String
      def frame_serial
        have = @f.fetch("i64", @rec, off(@frame, "serial"))
        give = @f.label
        keep = @f.label
        merge, (serial,) = @f.block(["i64"]) #: [String, [String]]
        @f.brif(@f.icmp("eq", have, imm(0)), give, keep)
        switch(keep)
        @f.jump(merge, [have])
        switch(give)
        @f.jump(merge, [kernel("zr_frame_serial", @rec)])
        switch(merge)
        serial
      end

      # In a method: a field of the method entry that it was called through.
      #: (String name) -> String
      def entry_field(name)
        @f.fetch("i64", arg_entry, off(@l.layout("MEntry"), name))
      end

      # A twin's cref: the one that its entry keeps in its `ivar` word, if
      # it is the cref of this entry, else the kernel's
      # (`zr_bmethod_cref`, which makes it at the first call).
      #: () -> String
      def twin_cref
        kept = entry_field("ivar")
        check = @f.label
        hit = @f.label
        miss = @f.cold(@f.label)
        merge, (cref,) = @f.block(["i64"]) #: [String, [String]]
        @f.brif(@f.icmp("eq", kept, imm(0)), miss, check)
        switch(check)
        @f.brif(@f.icmp("eq", @f.fetch("i64", kept, off(@cref_layout, "entry")), arg_entry), hit, miss)
        switch(hit)
        @f.jump(merge, [kept])
        switch(miss)
        @f.jump(merge, [kernel("zr_bmethod_cref", arg_entry)])
        switch(merge)
        cref
      end

      # In a block function: whether this Proc is a lambda. A twin is
      # always one, as `zr_bmethod_fn` makes the body's copy a lambda.
      #: () -> String
      def lambda?
        @f.icmp("ne", @twin_of ? imm(1) : proc_field("lambda"), imm(0))
      end

      # In a block function: `return`, `break` and `next` leave a lambda
      # with `v`. For a plain block, this runs the given Ruby block.
      #: (String v) { () -> void } -> void
      def unless_lambda(v)
        plain = @f.label
        own = @f.label
        @f.brif(lambda?, own, plain)
        switch(own)
        leave(through_ensures(v))
        switch(plain)
        yield
      end

      #: (Machine::Layout layout, String field) -> Integer
      def off(layout, field)
        layout.fields.fetch(field).first
      end

      #: (String name) -> String
      def global(name)
        @f.fetch("i64", static("globals"), 8 * @l.const(name))
      end

      # The innermost class of the cref: where a def or a constant goes.
      #: () -> String
      def cref_class
        kernel("zr_cref_klass", @cref)
      end

      #: (Integer i) -> Integer
      def value_offset(i)
        @frame.size + (8 * i)
      end
    end
  end
end
