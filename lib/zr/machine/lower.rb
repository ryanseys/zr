# frozen_string_literal: true

require_relative "../parse"
require_relative "../ir"
require_relative "../obj/model"
require_relative "../refused"
require_relative "../bytes"
require_relative "../config"
require_relative "description"
require_relative "function"

module Zr
  # The typed lowering of the kernel. A unit of one or more files, each
  # one `module Zr::Kern` of plain Ruby, contains imports (`module
  # Libc`), layouts (`class Name < Layout`), signatures, constants, and
  # defs typed by a `#:` comment. Each def lowers directly to one IR
  # function. The types are `i8 i32 word ptr value f64 bool void`, and a
  # view of a layout (`RString[s]`). A local gets its type
  # from its first assignment and is in a frame slot; `IR::Mem2Reg`
  # changes the slot to values when no other code takes its address. A
  # call goes to an import (`Libc.name`), to a def of the same unit, or
  # through a pointer (`Name.call`). zr refuses a form that the typed
  # lowering does not have, with a message that gives the form and the
  # line.
  module Machine
    class Refused < Zr::Refused
      attr_reader :line #: Integer?

      # Minitest copies an exception that it cannot marshal with only its
      # message, so a message alone is also accepted.
      #: (Prism::node? node, String message, ?String? file) -> void
      #: (String message) -> void
      def initialize(node, message = nil, file = nil)
        # @type var node: untyped
        if message
          @line = node.location.start_line
          super("#{file ? "#{file}:" : "line "}#{@line}: #{message}")
        else
          super(node)
        end
      end
    end

    # Compiles `source` to `[functions, data, raw]`: IR functions, the
    # data objects they refer to, and the names of the raw functions they
    # call.
    #: (String source, String file, ?symbols: Symbols) -> [Array[IR::Function], Array[Obj::Datum], Array[String]]
    def self.compile(source, file, symbols: Symbols.new)
      Lower.new([[source, file]], symbols).run
    end

    # Several files as one unit: every declaration is visible to every
    # file, in any order, and a def may call a def of any file. Only the
    # tests use it; a build uses `Machine.unit`.
    #: (Array[String] paths, ?symbols: Symbols) -> [Array[IR::Function], Array[Obj::Datum], Array[String]]
    def self.compile_unit(paths, symbols: Symbols.new)
      unit(paths, symbols: symbols).then { |u| [u.functions, u.data, u.raw] }
    end

    # Returns the compiled unit. Another lowering can read its layouts
    # and constants.
    #: (Array[String] paths, ?symbols: Symbols) -> Lower
    def self.unit(paths, symbols: Symbols.new)
      u = Lower.new(paths.map { |path| [File.read(path), path] }, symbols)
      u.run
      u
    end

    class Lower
      # @rbs @sources: Array[[String, String]]
      # @rbs @checked: bool
      # @rbs @imports: Hash[String, Import | Raw]
      # @rbs @consts: Hash[String, [Prism::node, String]]
      # @rbs @structs: Hash[String, [Prism::ClassNode, String]]
      # @rbs @class_fields: Hash[String, Array[[String, String, Prism::node]]]
      # @rbs @const_values: Hash[String, Integer]
      # @rbs @layouts: Hash[String, Layout]
      # @rbs @resolving: Array[String]
      # @rbs @sigs: Hash[String, Signature]
      # @rbs @next_bytes: Integer
      # @rbs @statics: Hash[String, Integer]
      # @rbs @globals: Hash[String, Integer]
      # @rbs @collectors: Array[String]
      # @rbs @collects: Set[String | Symbol]?
      # @rbs @inline: Hash[String, bool?]
      # @rbs @inlined: Array[String]
      # @rbs @any_thread: Array[String]
      # @rbs @file: String

      include Immediates

      attr_reader :functions #: Array[IR::Function]
      attr_reader :data #: Array[Obj::Datum]
      attr_reader :raw #: Array[String]
      attr_reader :symbols #: Symbols
      attr_reader :defs #: Hash[String, Def]

      #: (Array[[String, String]] sources, ?Symbols symbols, ?checked: bool) -> void
      def initialize(sources, symbols = Symbols.new, checked: Config.current.kernel_checked?)
        @sources = sources
        @symbols = symbols
        @checked = checked
        @imports = {}
        @defs = {}
        @consts = {}
        @structs = {}
        @class_fields = {}
        @const_values = {}
        @layouts = {}
        @resolving = []
        @sigs = {}
        @functions = []
        @data = []
        @raw = []
        @next_bytes = 0
        @statics = {}
        @globals = {}
        @collectors = []
        @collects = nil
        @inline = {}
        @inlined = []
        @any_thread = []
      end

      #: () -> [Array[IR::Function], Array[Obj::Datum], Array[String]]
      def run
        # @type ivar @collects: Set[String | Symbol]
        declare_all
        @collects = collecting_defs
        static(nil, ROOTS, 8) unless @collects.empty?
        @defs.each_value { |d| @functions << Function.new(self, d).lower }
        assign_effects
        [@functions, @data, @raw]
      end

      # Reads the declarations of every file, then folds each constant and
      # lays out each layout.
      #: () -> void
      def declare_all
        declare_files
        @consts.each_key { |name| const_for(name) }
        @structs.each_key { |name| struct_for(name) }
        @defs.each_value { |d| answers_import(d) }
      end

      # Reads the declarations of every file: the defs and their types, the
      # layouts, the imports, the signatures and the constants. The host
      # (`Host`) reads the kernel's types from here and lowers nothing. It
      # may load only some kernel files, so a layout is laid out only when
      # it is used (`struct_for`).
      #: () -> self
      def declare_files
        @sources.each do |source, file|
          result = Zr.parse(source, filepath: file)
          unless result.errors.empty?
            e = result.errors.first
            raise SyntaxError, "#{file}:#{e.location.start_line}: #{e.message}"
          end

          @file = file
          declare(kern_body(result.value.statements.body, result.value), Machine.annotations(result))
        end
        self
      end

      # Sets the effects (`IR::Effects`) of each def: the regions that its
      # stores write, plus the effects of the defs it calls (a fixpoint).
      # A store's region comes from the lowering or from the origin of its
      # address. An import writes what `Effects.import` returns. A raw
      # function and a call through a pointer write everything.
      # A store through an address of unknown origin writes `UNKNOWN`. It
      # also writes each guard word whose address escapes as a value
      # anywhere in the unit (passed, stored, compared), because a pointer
      # to that word can then be anywhere. The result goes to each
      # function's callees, and the description gives it to the program
      # lowering and to eval support.
      #: () -> void
      def assign_effects
        placed = @functions.to_h { |f| [f.name, placements(f)] }
        escaped = @functions.reduce(0) { |bits, f| bits | escaping_statics(f, placed.fetch(f.name)) }
        local = @functions.to_h { |f| [f.name, local_effects(f, placed.fetch(f.name), escaped)] }
        calls = @functions.to_h { |f| [f.name, f.callees.filter_map { |c| c.symbol if @defs.key?(c.symbol) }] }
        effects = local.dup
        loop do
          moved = false
          effects.each_key do |name|
            was = effects[name]
            now = calls.fetch(name).reduce(was) { |bits, callee| bits | effects.fetch(callee, IR::Effects::ALL) }
            next if now == was

            effects[name] = now
            moved = true
          end
          break unless moved
        end
        @defs.each_value { |d| d.effects = effects.fetch(d.name, IR::Effects::ALL) }
        @functions.each do |f|
          f.callees.each { |c| c.effects = effects.fetch(c.symbol, IR::Effects::ALL) }
        end
      end

      # Returns `{ value => [root, offset] }` for each value of `f` that is
      # the address of a slot (root `:slot`) or of a symbol, or that
      # address plus a constant. A root is a symbol name or `:slot`; the
      # callers test it for `:slot` with `!=`, which Steep does not follow.
      #: (IR::Function f) -> Hash[String, [untyped, Integer]]
      def placements(f)
        symbol_of = f.globals.to_h { |g| [g.gv, g.symbol] }
        const = {} #: Hash[String, Integer]
        placed = {} #: Hash[String, [untyped, Integer]]
        f.blocks.each do |b|
          b.insts.each do |i|
            case i.op
            when :iconst then const[i.results[0]] = i.args[0]
            when :stack_addr then placed[i.results[0]] = [:slot, 0]
            when :symbol_value then placed[i.results[0]] = [symbol_of.fetch(i.args[0]), 0]
            when :iadd
              a, k = i.args
              a, k = k, a if const.key?(a)
              placed[i.results[0]] = [placed[a][0], placed[a][1] + const.fetch(k)] if placed.key?(a) && const.key?(k)
            end
          end
        end
        placed
      end

      # Returns the region bits of each guard word (a gate, a stamp, the
      # task) whose address `f` uses as something other than the base of
      # a load or a store, or the addend of a constant. The `return` of an
      # inlined def (`zr_gates`, `zr_current_task_slot`) is not an escape.
      # No caller in this unit gets the address from a call. A caller in
      # a different unit stores through the address in its own function,
      # and the passes of that function do not know where such a store goes.
      #: (IR::Function f, Hash[String, [untyped, Integer]] placed) -> Integer
      def escaping_statics(f, placed)
        bits = 0
        answers = inline?(@defs.fetch(f.name))
        f.blocks.each do |b|
          b.insts.each do |i|
            next if i.op == :iadd && placed.key?(i.results[0])
            next if i.op == :return && answers

            i.args.each_with_index do |a, k|
              next unless (root = placed[a]&.first) && root != :slot
              next if (i.op == :load && k.zero?) || (i.op == :store && k == 1)

              region = IR::Effects.static_region(root)
              bits |= IR::Effects.bit(region) if region && region != :statics
            end
            i.targets&.each do |(_, args)|
              args.each do |a|
                root = placed[a]&.first
                region = root && root != :slot && IR::Effects.static_region(root)
                bits |= IR::Effects.bit(region) if region && region != :statics
              end
            end
          end
        end
        bits
      end

      # What `f`'s own instructions write.
      #: (IR::Function f, Hash[String, [untyped, Integer]] placed, Integer escaped) -> Integer
      def local_effects(f, placed, escaped)
        bits = 0
        by_fn = f.callees.to_h { |c| [c.fn, c] }
        f.blocks.each do |b|
          b.insts.each do |i|
            case i.op
            when :store then bits |= store_effects(i, placed, escaped)
            when :gates_set then bits |= IR::Effects.bit(:gates)
            when :call_indirect then bits |= IR::Effects::ALL
            when :call
              symbol = by_fn.fetch(i.callee).symbol
              bits |= IR::Effects.import(symbol) unless @defs.key?(symbol)
            end
          end
        end
        bits
      end

      # What one store writes: the region from the lowering, if there is
      # one; else the region of the static or slot of its address; else
      # all memory that a pointer can reach.
      #: (IR::Inst i, Hash[String, [untyped, Integer]] placed, Integer escaped) -> Integer
      def store_effects(i, placed, escaped)
        return IR::Effects.bit(i.region) if i.region

        root, at = placed[i.args[1]]
        return IR::Effects::UNKNOWN | escaped if root.nil?
        return 0 if root == :slot

        region = IR::Effects.static_region(root, at + i.offset)
        IR::Effects.bit(region || :statics)
      end

      # The static word that heads the chain of kernel root frames.
      ROOTS = "kroots"

      # Whether a call to `name` may run the collector: it is declared
      # with `Machine.collects`, or it reaches one that is, or it calls
      # through a pointer.
      #: (String | Symbol name) -> bool
      def collects?(name)
        # @type ivar @collects: Set[String | Symbol]
        @collects.include?(name)
      end

      # Whether `name` is declared `any_thread`: C may call it on a thread
      # that is not Ruby's (a worker that runs C without the GVL). Its
      # frame does not go on the chain of root frames, which a static
      # heads for the Ruby thread alone (ROOTS).
      #: (String name) -> bool
      def any_thread?(name) = @any_thread.include?(name)

      # Whether a call to `callee` lowers the callee's body in place of a
      # call. The kernel has many defs of one expression (a tag test, the
      # address of a static, a load from it). A call costs a frame, saved
      # registers and two branches, which is more than the body. The
      # collector makes such calls for each reference it reads.
      #
      # Only a small body that cannot run the collector, and that has no
      # `while` or `break`, is inlined. The def also lowers as a function,
      # so its symbol is available to callers that the kernel does not
      # see: eval support and `Machine.addr`.
      #: (Def | Import | Raw callee) -> bool?
      def inline?(callee)
        return false unless callee.is_a?(Def)

        @inline.fetch(callee.name) do
          @inline[callee.name] =
            if @inlined.include?(callee.name)
              tail_collecting?(callee.node.body) or
                refuse(callee.node, "#{callee.name} is `Machine.inline`, so it may run the collector only in the call that ends an arm")
            else
              !collects?(callee.name) && (body = callee.node.body) && small?(body, [INLINE_NODES])
            end
        end
      end

      # A body declared `Machine.inline` (of any size) must run the
      # collector only in the last call of an arm of its last `if`, and
      # the arguments of that call must not collect. That call gives the
      # value of the body, so the body uses no Value after a collection.
      # The call roots its own arguments. The caller roots its values as
      # it does around a call.
      #: (Prism::node? node) -> bool
      def tail_collecting?(node)
        case node
        when nil then true
        when Prism::StatementsNode
          *init, last = node.body
          init.none? { |s| collecting?(s) } && tail_collecting?(last)
        when Prism::IfNode
          !collecting?(node.predicate) && tail_collecting?(node.statements) && tail_collecting?(node.subsequent)
        when Prism::ElseNode then tail_collecting?(node.statements)
        # `return f(x)` ends an arm the same as `f(x)`: the jump passes
        # the result, and no value of the body is live after it.
        when Prism::ReturnNode then tail_collecting?(node.arguments&.arguments&.first)
        when Prism::CallNode then jumpless?(node) && !collecting?(node.receiver) && !collecting?(node.arguments)
        else jumpless?(node) && !collecting?(node)
        end
      end

      #: (Prism::node? node) -> bool
      def collecting?(node) = calls_in(node).any? { |name| collects?(name) }

      # No `while` or `break`, because they have a different meaning in
      # the caller.
      #: (Prism::node node) -> bool
      def jumpless?(node)
        return false if node.is_a?(Prism::WhileNode) || node.is_a?(Prism::BreakNode)

        node.compact_child_nodes.all? { |c| jumpless?(c) }
      end

      # The maximum number of Prism nodes in an inlined body.
      INLINE_NODES = 32

      # A `return` is permitted: when inlined, it is a jump to the end of
      # the body (`Function#ret`). A `while` or a `break` is not, because
      # the roots of a loop and the target of a break belong to the def.
      #
      # The `Libc` of an import call is not a node, and `Name.call(p)`
      # counts one more. The `Name[p]` of a field access is not a node,
      # and the arguments of a field write are not one either. Thus the
      # count is the same as in the forms that the kernel was written in
      # before (`Machine.call(:name, p)`, `Name.f(p)`, `Name.set_f(p, v)`),
      # and the same defs are inlined.
      #: (Prism::node node, Array[Integer] budget) -> bool
      def small?(node, budget)
        budget[0] -= 1 unless libc?(node) || layout_view?(node)
        budget[0] += 1 if node.is_a?(Prism::CallNode) && node.attribute_write? && layout_view?(node.receiver)
        budget[0] -= 1 if node.is_a?(Prism::CallNode) && node.name == :call && sig_read?(node.receiver)
        return false if budget[0].negative?
        return false if node.is_a?(Prism::WhileNode) || node.is_a?(Prism::BreakNode)

        node.compact_child_nodes.all? { |c| small?(c, budget) }
      end

      # Whether `node` is `Name[p]` of a layout `Name`.
      #: (Prism::node? node) -> bool
      def layout_view?(node)
        node.is_a?(Prism::CallNode) && node.name == :[] && (receiver = node.receiver).is_a?(Prism::ConstantReadNode) &&
          !struct_for(receiver.name.to_s).nil?
      end

      # The defs that can run the collector. A fixpoint over the calls of
      # each body finds them.
      #: () -> Set[String | Symbol]
      def collecting_defs
        calls = @defs.transform_values { |d| calls_in(d.node.body) }
        set = @collectors.to_set #: Set[String | Symbol]
        set << :indirect
        loop do
          grown = @defs.each_key.select { |name| !set.include?(name) && calls.fetch(name).any? { |c| set.include?(c) } }
          break if grown.empty?

          set.merge(grown)
        end
        set
      end

      # The names a body calls: defs by name, and `:indirect` for a
      # `Machine.call`.
      #: (Prism::node? node, ?Array[String | Symbol] into) -> Array[String | Symbol]
      def calls_in(node, into = [])
        return into if node.nil?

        if node.is_a?(Prism::CallNode)
          if node.receiver.nil? && @defs.key?(node.name.to_s)
            into << node.name.to_s
          elsif node.name == :call && sig_read?(node.receiver)
            into << :indirect
          end
        end
        node.compact_child_nodes.each { |c| calls_in(c, into) }
        into
      end

      # The module of the kernel. Each kernel file is one
      # `module Zr::Kern ... end` of plain Ruby.
      KERN = "Zr::Kern"

      # The statements in the module of a file.
      #: (Array[Prism::node] statements, Prism::node node) -> Array[Prism::node]
      def kern_body(statements, node)
        mod = statements.first if statements.one?
        refuse(statements.first || node, "a kernel file is one `module #{KERN}`") unless mod.is_a?(Prism::ModuleNode)
        refuse(mod, "the kernel's module is #{KERN}") unless mod.constant_path.slice == KERN
        body = mod.body
        refuse(body, "rescue and ensure are not in the kernel subset") if body.is_a?(Prism::BeginNode)
        body&.body || []
      end

      # The declarations of a file. A call to an import is
      # `Libc.name(...)`, and a bare call goes to a def:
      #
      #   module Libc                          C functions, each `def self.name(...) = Machine.import`
      #   class Name < Layout                  a layout, one `attr_accessor :field #: type` for each field
      #   module Name                          a signature, `def self.call(fn, ...) = Machine.indirect`
      #   NAME = 1 << 4                        a constant
      #   inline :name, collects :name         as `Machine.inline` and `Machine.collects`
      #   any_thread :name                     a def that C may call on any thread (`any_thread?`)
      #   #: (types) -> type, then a def       a def (`def_type`); `= Machine.raw` is one the backend delivers
      #: (Array[Prism::node] statements, Hash[Integer, String] annotations) -> void
      def declare(statements, annotations)
        statements.each do |node|
          case node
          when Prism::ConstantWriteNode then add_const(node, node.name.to_s)
          when Prism::ClassNode then declare_layout(node, annotations)
          when Prism::ModuleNode then declare_module(node, annotations)
          when Prism::DefNode
            if stub(node) == :raw
              add_raw(node, node.name.to_s, def_type(node, annotations))
            else
              add_def(node, def_type(node, annotations))
            end
          when Prism::CallNode
            # The guards below check the class of each argument.
            args = node.arguments&.arguments || [] #: Array[untyped]
            if node.receiver.nil? && %i[inline collects any_thread].include?(node.name)
              refuse(node, "`#{node.name}` takes the symbol of a def") unless args.one? && args.first.is_a?(Prism::SymbolNode)
              { inline: @inlined, collects: @collectors, any_thread: @any_thread }.fetch(node.name) << args.first.unescaped
            else
              refuse(node, "a statement that is not a declaration or a def")
            end
          else
            refuse(node, "a statement that is not a declaration or a def")
          end
        end
        # Each def took its own comment, so a comment left here has no def.
        line, = annotations.first
        raise Refused, "#{@sources.size > 1 ? "#{@file}:" : "line "}#{line}: a `#:` comment that no def follows" if line
      end

      # The type of a def: the `#:` comment on the line above it, which is
      # inline RBS such as `#: (i32, ptr) -> i32`.
      #: (Prism::DefNode node, Hash[Integer, String] annotations) -> [Array[String], String]
      def def_type(node, annotations)
        text = annotations.delete(node.location.start_line - 1)
        refuse(node, "a def has no `#: (types) -> type` above it") unless text
        Machine.def_type(text) or
          refuse(node, "a def's type is `#: (types) -> type`, each type one of #{RBS_TYPES.keys.join(" ")}")
      end

      LAYOUT_FIELD = "a layout's field is `attr_accessor :name #: type` (`attr_reader` for an embedded layout)"

      # `class Name < Layout` with one `attr_accessor :field #: type` for
      # each field, in order. The type is a kernel type or a layout, which
      # is embedded in place and has only a reader.
      #: (Prism::ClassNode node, Hash[Integer, String] annotations) -> void
      def declare_layout(node, annotations)
        path = node.constant_path
        unless path.is_a?(Prism::ConstantReadNode) && node.superclass&.slice == "Layout"
          refuse(node, "a class of the kernel is a layout, `class Name < Layout`")
        end
        body = node.body
        refuse(body, LAYOUT_FIELD) unless body.nil? || body.is_a?(Prism::StatementsNode)
        name = path.name.to_s
        @class_fields[name] = (body&.body || []).map do |attr|
          args = attr.arguments&.arguments if attr.is_a?(Prism::CallNode) && attr.receiver.nil? && %i[attr_accessor attr_reader].include?(attr.name)
          field = args.first if args&.one?
          refuse(attr, LAYOUT_FIELD) unless field.is_a?(Prism::SymbolNode)
          type = annotations.delete(attr.location.start_line).to_s[/\A#:\s*(\w+)\s*\z/, 1] or refuse(attr, LAYOUT_FIELD)
          [field.unescaped, RBS_TYPES.fetch(type, type), attr]
        end
        add_struct(node, name)
      end

      # `module Libc` declares C functions, each a typed
      # `def self.name(...) = Machine.import`, called as `Libc.name(...)`.
      # Any other module is the signature of a call through a pointer, one
      # typed `def self.call(fn, ...) = Machine.indirect`, called as
      # `Name.call(p, ...)`.
      #: (Prism::ModuleNode node, Hash[Integer, String] annotations) -> void
      def declare_module(node, annotations)
        path = node.constant_path
        refuse(node, "a module of the kernel is `module Libc` or a signature") unless path.is_a?(Prism::ConstantReadNode)
        body = node.body
        defs = body.is_a?(Prism::StatementsNode) ? body.body : [] #: Array[Prism::node]
        libc = path.name == :Libc
        refuse(node, "a signature is one `def self.call(fn, ...) = Machine.indirect`") unless libc || defs.one?
        defs.each do |d|
          refuse(d, "a module of the kernel has only `def self.name(...)`") unless d.is_a?(Prism::DefNode) && d.receiver.is_a?(Prism::SelfNode)
          params, ret = def_type(d, annotations)
          refuse(d, "the `#:` type has #{params.size} types for #{stub_arity(d)} parameters") if stub_arity(d) != params.size
          if libc
            refuse(d, "an import is `def self.name(...) = Machine.import`") unless stub(d) == :import
            refuse(d, "#{d.name} is already imported") if @imports.key?(d.name.to_s)
            @imports[d.name.to_s] = Import.new(d.name.to_s, params, ret, import_module(d))
          else
            refuse(d, "a signature is `def self.call(fn, ...) = Machine.indirect`") unless d.name == :call && stub(d) == :indirect
            refuse(d, "a signature's first parameter is the function's ptr") unless params.first == "Ptr"
            name = path.name.to_s
            refuse(node, "#{name} is already a constant") if @consts.key?(name) || @structs.key?(name)
            add_sig(name, params.drop(1), ret)
          end
        end
      end

      # The kind of a def whose body is only `Machine.import`,
      # `Machine.indirect` or `Machine.raw`: a declaration with no body of
      # its own. Nil for a def with a body.
      #: (Prism::DefNode d) -> Symbol?
      def stub(d)
        body = d.body
        call = body.body.first if body.is_a?(Prism::StatementsNode) && body.body.one?
        return unless call.is_a?(Prism::CallNode) && machine?(call.receiver)

        call.name if %i[import indirect raw].include?(call.name)
      end

      #: (Prism::DefNode d) -> Integer
      def stub_arity(d)
        params = d.parameters
        refuse(d, "a declaration takes required parameters only") if params && params.child_nodes.compact.size != params.requireds.size
        params ? params.requireds.size : 0
      end

      # The wasm module of an import: `Machine.import(from: "module")`, or
      # nil for a symbol that the linker finds.
      #: (Prism::DefNode d) -> String?
      def import_module(d)
        body = d.body #: Prism::StatementsNode
        call = body.body.first #: Prism::CallNode
        args = call.arguments&.arguments or return
        hash = args.first if args.one?
        pair = hash.elements.first if hash.is_a?(Prism::KeywordHashNode) && hash.elements.one?
        key = pair.key if pair.is_a?(Prism::AssocNode)
        value = pair.value if pair.is_a?(Prism::AssocNode)
        unless key.is_a?(Prism::SymbolNode) && key.unescaped == "from" && value.is_a?(Prism::StringNode)
          refuse(call, "an import names its wasm module with `from: \"module\"`")
        end
        value.unescaped
      end

      #: (Prism::ConstantWriteNode node, String name) -> void
      def add_const(node, name)
        refuse(node, "#{name} is already a constant") if @consts.key?(name)
        refuse(node, "#{name} is already a struct") if @structs.key?(name)
        refuse(node, "#{name} is already a signature") if @sigs.key?(name)
        @consts[name] = [node.value, @file]
      end

      #: (String name, Array[String] params, String ret) -> void
      def add_sig(name, params, ret)
        @sigs[name] = Signature.new(name, params, ret)
      end

      # A raw function. Its signature must be the one the backend delivers.
      #: (Prism::node node, String name, [Array[String], String] sig) -> void
      def add_raw(node, name, sig)
        raw = RAW.fetch(name) { refuse(node, "no raw function named #{name}") }
        refuse(node, "#{name} is #{Machine.rbs_type(raw.params, raw.ret)}") if sig != [raw.params, raw.ret]
        @imports[name] = raw
        @raw << name
      end

      #: (Prism::DefNode d, [Array[String], String] sig) -> void
      def add_def(d, sig)
        params, ret = sig
        refuse(d, "a machine def's name is letters, digits and underscores") unless d.name.to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
        names = (d.parameters&.requireds || []).map do |p|
          refuse(d, "a machine def takes required parameters only") unless p.is_a?(Prism::RequiredParameterNode)
          p.name.to_s
        end
        refuse(d, "the `#:` type has #{params.size} types for #{names.size} parameters") if names.size != params.size
        refuse(d, "a machine def takes required parameters only") if (parameters = d.parameters) && parameters.child_nodes.compact.size != names.size
        refuse(d, "a def has a receiver; the kernel's defs are plain `def name`") if d.receiver
        refuse(d, "#{d.name} is defined twice; the first is in #{@defs[d.name.to_s].file}") if @defs.key?(d.name.to_s)
        typed = names.zip(params) #: Array[[String, String]]
        @defs[d.name.to_s] = Def.new(d.name.to_s, typed, ret, d, @file)
      end

      # A def with the name of an import replaces that import for its
      # calls. An OS layer uses this to define a libc call that its OS
      # does not have. The def must have the signature of the import, or
      # a call written for one would pass the wrong arguments to the other.
      #: (Def d) -> void
      def answers_import(d)
        import = @imports[d.name] or return
        refuse(d.node, "#{d.name} is a raw function, and cannot be defined") if import.is_a?(Raw)
        return if d.params.map(&:last) == import.params && d.ret == import.ret

        refuse(d.node, "#{d.name} answers an import of #{Machine.rbs_type(import.params, import.ret)}, and its type differs")
      end

      # A constant's value: an integer, a constant, a struct's size, or an
      # operator over those, folded here.
      #: (Prism::node? node) -> Integer
      def fold(node)
        case node
        when Prism::IntegerNode then node.value
        when Prism::ParenthesesNode
          body = node.body
          refuse(node, CONSTANT_FORMS) unless body.is_a?(Prism::StatementsNode)
          fold(body.body.first)
        when Prism::ConstantReadNode
          const_for(node.name.to_s) or refuse(node, "#{node.name} is not a constant here")
        when Prism::CallNode
          receiver = node.receiver
          args = node.arguments&.arguments
          if receiver.is_a?(Prism::ConstantReadNode) && node.name == :size && (layout = struct_for(receiver.name.to_s))
            layout.size
          elsif receiver && args && args.size == 1 && %i[+ - * << >> | & ^].include?(node.name)
            # `name` is one of the Integer operators above.
            fold(receiver).public_send(node.name, fold(args.first)) #: Integer
          else
            refuse(node, CONSTANT_FORMS)
          end
        else
          refuse(node, CONSTANT_FORMS)
        end
      end

      CONSTANT_FORMS = "a constant is an integer, a constant, a struct's size, or an operator over those"

      # `fold` for a def in `file`, so that a refusal gives that file and
      # not the last file declared.
      #: (String file, Prism::node? node) -> Integer
      def fold_in(file, node)
        outer = @file
        begin
          @file = file
          fold(node)
        ensure
          @file = outer
        end
      end

      #: (Prism::ClassNode node, String name) -> void
      def add_struct(node, name)
        refuse(node, "#{name} is already a struct") if @structs.key?(name)
        refuse(node, "#{name} is already a constant") if @consts.key?(name) || @sigs.key?(name)
        @structs[name] = [node, @file]
      end

      # Each field at its natural alignment; a field of a struct type is
      # embedded in place.
      #: (String name) -> Layout
      def layout(name)
        off = 0
        align = 1
        rows = @class_fields.fetch(name).to_h do |field, type, at_node|
          size, a = field_shape(at_node, type)
          off = Bytes.align(off, a)
          align = [align, a].max
          at = off
          off += size
          [field, [at, type]] #: [String, [Integer, String]]
        end
        size = Bytes.align(off, align)
        Layout.new(name, rows, size, align)
      end

      # `[size, align]` of a field of `type`.
      #: (Prism::node node, String type) -> [Integer, Integer]
      def field_shape(node, type)
        if (layout = struct_for(type))
          return [layout.size, layout.align]
        end

        case TYPES.fetch(type) { refuse(node, "a field's type is a type or a struct") }
        when "i8" then [1, 1]
        when "i32" then [4, 4]
        when nil then refuse(node, "a field cannot be Void")
        else [8, 8]
        end
      end

      #: (Prism::node? node) -> bool
      def machine?(node)
        node.is_a?(Prism::ConstantReadNode) && node.name == :Machine
      end

      # Whether the defs check their operators (`ZR_KERNEL_CHECKED`,
      # `Function#check_wrap`).
      #: () -> bool
      def checked? = @checked

      #: (Prism::node? node) -> bool
      def libc?(node)
        node.is_a?(Prism::ConstantReadNode) && node.name == :Libc
      end

      # Whether `node` names a signature, a `module Name` with a typed `call`.
      #: (Prism::node? node) -> bool
      def sig_read?(node)
        node.is_a?(Prism::ConstantReadNode) && @sigs.key?(node.name.to_s)
      end

      #: (String name) -> (Import | Raw)?
      def import_for(name)
        @imports[name]
      end

      #: (String name) -> Def?
      def def_for(name)
        @defs[name]
      end

      # The names this unit declares, for a `Description` to read.
      #: () -> Hash[String, Def]
      def declared_defs = @defs
      #: () -> Array[String]
      def declared_consts = @consts.keys
      #: () -> Array[String]
      def declared_structs = @structs.keys
      #: () -> Hash[String, Import | Raw]
      def declared_imports = @imports
      #: () -> Hash[String, Signature]
      def declared_sigs = @sigs

      # The file that declares the constant `name`. Only the tests use it
      # (test/unit/os_api_test.rb).
      #: (String name) -> String
      def const_file(name) = @consts.fetch(name).last

      # A constant's value. It is folded on first use, so a declaration
      # can refer to a constant from a later file.
      #: (String name) -> Integer?
      def const_for(name)
        resolve(@consts, @const_values, name) do |node|
          value = fold(node)
          # CRuby keeps the constant as written, so one at or above 2**63
          # is not the Word it is here.
          refuse(node, "#{name} is outside a signed Word; write its bits as a negative number") unless value.between?(-(1 << 63), (1 << 63) - 1)
          value
        end
      end

      #: (String name) -> Layout?
      def struct_for(name)
        resolve(@structs, @layouts, name) { layout(name) }
      end

      #: [N < Prism::node, T] (Hash[String, [N, String]] declared, Hash[String, T] resolved, String name) { (N) -> T } -> T?
      def resolve(declared, resolved, name)
        was = nil #: String?
        begin
          return resolved[name] if resolved.key?(name)
          return unless (node, file = declared[name])

          refuse(node, "#{name} depends on itself") if @resolving.include?(name)
          @resolving << name
          was, @file = @file, file
          resolved[name] = yield(node)
        ensure
          @file = was if was
          @resolving.delete(name)
        end
      end

      # Whether this is a unit of several files. Its refusals give the file.
      #: () -> bool
      def unit?
        @sources.size > 1
      end

      # The caller tests `sig_read?` first.
      #: (String name) -> Signature
      def sig_for(name)
        @sigs.fetch(name)
      end

      # A read-only byte string, as a data object of this unit.
      #: (String string) -> String
      def bytes(string)
        name = "zr_bytes_#{@next_bytes}"
        @next_bytes += 1
        @data << Obj::Datum.new(name, :text_const, string, align: 1)
        name
      end

      # A zeroed, writable area of this unit, one for each name.
      #: (Prism::node? node, String name, Integer size) -> String
      def static(node, name, size)
        if @statics.key?(name)
          refuse(node, "#{name} is #{@statics[name]} bytes, not #{size}") if @statics[name] != size
        else
          @statics[name] = size
          @data << Obj::Datum.new("zr_static_#{name}", :bss, size, align: 16)
        end
        "zr_static_#{name}"
      end

      # An exported, zeroed area that C code reads by its own name, as a C
      # extension reads `rb_cObject`: `Machine.global(:rb_cObject)` is a
      # word, and `Machine.global(:ruby_hexdigits, 33)` a table of bytes.
      #: (Prism::node? node, String name, Integer size) -> String
      def global(node, name, size)
        if @globals.key?(name)
          refuse(node, "#{name} is #{@globals[name]} bytes, not #{size}") if @globals[name] != size
        else
          @globals[name] = size
          @data << Obj::Datum.new(name, :bss, size, align: 8, linkage: :export)
        end
        name
      end

      #: (Prism::node? node, String message) -> bot
      def refuse(node, message)
        raise Refused.new(node, message, @sources.size > 1 ? @file : nil)
      end
    end
  end
end
