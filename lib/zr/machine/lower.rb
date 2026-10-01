# frozen_string_literal: true

require_relative "../parse"
require_relative "../ir"
require_relative "../obj/model"
require_relative "../refused"
require_relative "../bytes"
require_relative "description"
require_relative "function"

module Zr
  # The machine dialect: Ruby syntax, machine semantics. A unit of one or
  # more files contains `Machine.import`, `Machine.struct`, `Machine.sig`
  # and constant declarations, and `sig`-typed `machine def`s. Each def
  # lowers directly to one IR function. The types are `I8 I32 Word Ptr
  # Value F64 Bool Void`. A local gets its type from its first assignment
  # and is in a frame slot; `IR::Mem2Reg` changes the slot to values when
  # no other code takes its address. A call goes to an import, to a def
  # of the same unit, or through a pointer with `Machine.call`. zr
  # refuses a form outside the dialect, with a message that gives the
  # form and the line.
  module Machine
    class Refused < Zr::Refused
      attr_reader :line

      # Minitest copies an exception that it cannot marshal with only its
      # message, so a message alone is also accepted.
      def initialize(node, message = nil, file = nil)
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
    def self.compile(source, file, symbols: Symbols.new)
      Lower.new([[source, file]], symbols).run
    end

    # Several files as one unit: every declaration is visible to every
    # file, in any order, and a def may call a def of any file. Only the
    # tests use it; a build uses `Machine.unit`.
    def self.compile_unit(paths, symbols: Symbols.new)
      unit(paths, symbols: symbols).then { |u| [u.functions, u.data, u.raw] }
    end

    # Returns the compiled unit. Another lowering can read its layouts
    # and constants.
    def self.unit(paths, symbols: Symbols.new)
      u = Lower.new(paths.map { |path| [File.read(path), path] }, symbols)
      u.run
      u
    end

    class Lower
      include Immediates

      attr_reader :functions, :data, :raw, :symbols, :defs

      def initialize(sources, symbols = Symbols.new)
        @sources = sources
        @symbols = symbols
        @imports = {}
        @defs = {}
        @consts = {}
        @structs = {}
        @const_values = {}
        @layouts = {}
        @resolving = []
        @sigs = {}
        @functions = []
        @data = []
        @raw = []
        @next_bytes = 0
        @statics = {}
        @collectors = []
        @collects = nil
        @inline = {}
        @inlined = []
        @plain = Set.new
      end

      def run
        @sources.each do |source, file|
          result = Zr.parse(source, filepath: file)
          unless result.errors.empty?
            e = result.errors.first
            raise SyntaxError, "#{file}:#{e.location.start_line}: #{e.message}"
          end

          @file = file
          statements = result.value.statements.body
          if (body = kern_body(statements))
            @plain << file
            declare_plain(body)
          else
            declare(statements)
          end
        end
        @consts.each_key { |name| const_for(name) }
        @structs.each_key { |name| struct_for(name) }
        @defs.each_value { |d| answers_import(d) }
        @collects = collecting_defs
        static(nil, ROOTS, 8) unless @collects.empty?
        @defs.each_value { |d| @functions << Function.new(self, d).lower }
        assign_effects
        [@functions, @data, @raw]
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
      # address plus a constant.
      def placements(f)
        symbol_of = f.globals.to_h { |g| [g.gv, g.symbol] }
        const = {}
        placed = {}
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
      def collects?(name)
        @collects.include?(name)
      end

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
      def inline?(callee)
        return false unless callee.is_a?(Def)

        @inline.fetch(callee.name) do
          @inline[callee.name] =
            if @inlined.include?(callee.name)
              tail_collecting?(callee.node.body) or
                refuse(callee.node, "#{callee.name} is `Machine.inline`, so it may run the collector only in the call that ends an arm")
            else
              !collects?(callee.name) && callee.node.body && small?(callee.node.body, [INLINE_NODES])
            end
        end
      end

      # A body declared `Machine.inline` (of any size) must run the
      # collector only in the last call of an arm of its last `if`, and
      # the arguments of that call must not collect. That call gives the
      # value of the body, so the body uses no Value after a collection.
      # The call roots its own arguments. The caller roots its values as
      # it does around a call.
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

      def collecting?(node) = calls_in(node).any? { |name| collects?(name) }

      # No `while` or `break`, because they have a different meaning in
      # the caller.
      def jumpless?(node)
        return false if node.is_a?(Prism::WhileNode) || node.is_a?(Prism::BreakNode)

        node.compact_child_nodes.all? { |c| jumpless?(c) }
      end

      # The maximum number of Prism nodes in an inlined body.
      INLINE_NODES = 32

      # A `return` is permitted: when inlined, it is a jump to the end of
      # the body (`Function#ret`). A `while` or a `break` is not, because
      # the roots of a loop and the target of a break belong to the def.
      def small?(node, budget)
        budget[0] -= 1
        return false if budget[0].negative?
        return false if node.is_a?(Prism::WhileNode) || node.is_a?(Prism::BreakNode)

        node.compact_child_nodes.all? { |c| small?(c, budget) }
      end

      # The defs that can run the collector. A fixpoint over the calls of
      # each body finds them.
      def collecting_defs
        calls = @defs.transform_values { |d| calls_in(d.node.body) }
        set = @collectors.to_set
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
      def calls_in(node, into = [])
        return into if node.nil?

        if node.is_a?(Prism::CallNode)
          if node.receiver.nil? && @defs.key?(node.name.to_s)
            into << node.name.to_s
          elsif node.name == :call && (machine?(node.receiver) || sig_read?(node.receiver))
            into << :indirect
          end
        end
        node.compact_child_nodes.each { |c| calls_in(c, into) }
        into
      end

      # The file's declarations: imports, structs, signatures, constants,
      # and each `sig` with its def.
      def declare(statements)
        pending_sig = nil
        statements.each do |node|
          if node.is_a?(Prism::ConstantWriteNode)
            add_const(node, node.name.to_s)
            next
          end
          refuse(node, "a statement that is not a declaration or a machine def") unless node.is_a?(Prism::CallNode)
          case node.name
          when :struct
            refuse(node, "a struct is `Machine.struct :Name, field: Type, ...`") unless machine?(node.receiver)
            declare_struct(node)
          when :sig
            if machine?(node.receiver)
              name, sig = node.arguments&.arguments
              refuse(node, "a named signature is `Machine.sig :name, [types] => type`") unless name.is_a?(Prism::SymbolNode) && sig
              add_sig(name.unescaped, *signature(sig))
            else
              refuse(node, "a sig is `sig [types] => type`") unless node.receiver.nil?
              pending_sig = signature(node.arguments.arguments.first)
            end
          when :import
            refuse(node, "an import is `Machine.import \"name\", [types] => type`") unless machine?(node.receiver)
            name, sig = node.arguments.arguments
            add_import(name.unescaped, sig)
          when :collects
            refuse(node, "`Machine.collects` takes the symbol of a machine def") unless machine?(node.receiver) && node.arguments&.arguments&.first.is_a?(Prism::SymbolNode)
            @collectors << node.arguments.arguments.first.unescaped
          when :inline
            refuse(node, "`Machine.inline` takes the symbol of a machine def") unless machine?(node.receiver) && node.arguments&.arguments&.first.is_a?(Prism::SymbolNode)
            @inlined << node.arguments.arguments.first.unescaped
          when :raw
            refuse(node, "a raw function is `Machine.raw \"name\"`") unless machine?(node.receiver)
            add_raw(node, node.arguments.arguments.first.unescaped)
          when :machine
            d = node.arguments&.arguments&.first
            refuse(node, "`machine` takes a def") unless d.is_a?(Prism::DefNode)
            refuse(d, "a machine def has no sig ahead of it") if pending_sig.nil?
            add_def(d, pending_sig)
            pending_sig = nil
          else
            refuse(node, "`#{node.name}` is not in the kernel dialect at the top level")
          end
        end
      end

      # The module of the kernel in plain Ruby. A file that is one
      # `module Zr::Kern ... end` is in the plain form; any other file is
      # in the dialect form. Both forms lower to the same IR, so the
      # files can move one group at a time (A6).
      KERN = "Zr::Kern"

      # The statements in the module of a file in the plain form, or nil
      # for a file in the dialect form.
      def kern_body(statements)
        return unless statements.one? && (mod = statements.first).is_a?(Prism::ModuleNode)

        refuse(mod, "the kernel's module is #{KERN}") unless mod.constant_path.slice == KERN
        mod.body&.body || []
      end

      # Whether `file` is in the plain form. In that form, a call to an
      # import is `Libc.name(...)`, and a bare call goes to a def.
      def plain?(file) = @plain.include?(file)

      # The declarations of a file in the plain form:
      #
      #   Libc.import :name, [types] => type   a C function, called as `Libc.name(...)`
      #   Name = layout field: Type, ...       a struct
      #   Name = fn [types] => type            a signature, called as `Name.call(pointer, ...)`
      #   NAME = 1 << 4                        a constant
      #   inline :name, collects :name         as `Machine.inline` and `Machine.collects`
      #   raw :name, [types] => type           a function that the backend delivers
      #   sig [types] => type, then a def      a def
      def declare_plain(statements)
        pending_sig = nil
        statements.each do |node|
          case node
          when Prism::ConstantWriteNode then declare_plain_const(node)
          when Prism::DefNode
            refuse(node, "a def has no sig ahead of it") if pending_sig.nil?
            add_def(node, pending_sig)
            pending_sig = nil
          when Prism::CallNode
            args = node.arguments&.arguments || []
            if libc?(node.receiver) && node.name == :import
              refuse(node, "an import is `Libc.import :name, [types] => type`") unless args.size == 2 && args.first.is_a?(Prism::SymbolNode)
              add_import(args.first.unescaped, args.last)
            elsif node.receiver.nil? && node.name == :sig
              refuse(node, "a sig is `sig [types] => type`") unless args.one?
              pending_sig = signature(args.first)
            elsif node.receiver.nil? && %i[inline collects].include?(node.name)
              refuse(node, "`#{node.name}` takes the symbol of a def") unless args.one? && args.first.is_a?(Prism::SymbolNode)
              (node.name == :inline ? @inlined : @collectors) << args.first.unescaped
            elsif node.receiver.nil? && node.name == :raw
              refuse(node, "a raw function is `raw :name, [types] => type`") unless args.size == 2 && args.first.is_a?(Prism::SymbolNode)
              add_raw(node, args.first.unescaped, signature(args.last))
            else
              refuse(node, "a statement that is not a declaration or a def")
            end
          else
            refuse(node, "a statement that is not a declaration or a def")
          end
        end
      end

      # `Name = layout ...`, `Name = fn ...`, or a constant.
      def declare_plain_const(node)
        name = node.name.to_s
        value = node.value
        kind = value.name if value.is_a?(Prism::CallNode) && value.receiver.nil?
        args = value.arguments&.arguments if kind
        case kind
        when :layout
          refuse(node, "a struct is `Name = layout field: Type, ...`") unless args&.one? && args.first.is_a?(Prism::KeywordHashNode)
          add_struct(value, name)
        when :fn
          refuse(node, "a signature is `Name = fn [types] => type`") unless args&.one?
          refuse(node, "#{name} is already a constant") if @consts.key?(name) || @structs.key?(name)
          add_sig(name, *signature(args.first))
        else
          add_const(node, name)
        end
      end

      def add_const(node, name)
        refuse(node, "#{name} is already a constant") if @consts.key?(name)
        refuse(node, "#{name} is already a struct") if @structs.key?(name)
        refuse(node, "#{name} is already a signature") if @sigs.key?(name)
        @consts[name] = [node.value, @file]
      end

      def add_sig(name, params, ret)
        @sigs[name] = Signature.new(name, params, ret)
      end

      def add_import(name, sig)
        params, ret, from = import_signature(sig)
        @imports[name] = Import.new(name, params, ret, from)
      end

      # A raw function. The plain form repeats its signature, which must
      # be the one the backend delivers.
      def add_raw(node, name, sig = nil)
        raw = RAW.fetch(name) { refuse(node, "no raw function named #{name}") }
        refuse(node, "#{name} is [#{raw.params.join(", ")}] => #{raw.ret}") if sig && sig != [raw.params, raw.ret]
        @imports[name] = raw
        @raw << name
      end

      def add_def(d, sig)
        params, ret = sig
        refuse(d, "a machine def's name is letters, digits and underscores") unless d.name.to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
        names = (d.parameters&.requireds || []).map { |p| p.name.to_s }
        refuse(d, "the sig has #{params.size} types for #{names.size} parameters") if names.size != params.size
        refuse(d, "a machine def takes required parameters only") if d.parameters && d.parameters.child_nodes.compact.size != names.size
        refuse(d, "a def has a receiver; the kernel's defs are plain `def name`") if d.receiver
        refuse(d, "#{d.name} is defined twice; the first is in #{@defs[d.name.to_s].file}") if @defs.key?(d.name.to_s)
        @defs[d.name.to_s] = Def.new(d.name.to_s, names.zip(params), ret, d, @file)
      end

      # Returns an import's `[[type names], type name, module]`. `from:`
      # gives the wasm module of the import, as one more pair in the same
      # hash.
      def import_signature(node)
        refuse(node, "a signature is `[types] => type`") unless node.is_a?(Prism::KeywordHashNode) && node.elements.size.between?(1, 2)
        pair, from = node.elements
        return [*pair_signature(pair), nil] unless from
        unless from.key.is_a?(Prism::SymbolNode) && from.key.unescaped == "from" && from.value.is_a?(Prism::StringNode)
          refuse(from, "an import names its wasm module with `from: \"module\"`")
        end

        [*pair_signature(pair), from.value.unescaped]
      end

      # A def with the name of an import replaces that import for its
      # calls. An OS layer uses this to define a libc call that its OS
      # does not have. The def must have the signature of the import, or
      # a call written for one would pass the wrong arguments to the other.
      def answers_import(d)
        import = @imports[d.name] or return
        refuse(d.node, "#{d.name} is a raw function, and cannot be defined") if import.is_a?(Raw)
        return if d.params.map(&:last) == import.params && d.ret == import.ret

        refuse(d.node, "#{d.name} answers an import of [#{import.params.join(", ")}] => #{import.ret}, and its sig differs")
      end

      # `[types] => type` as `[[type names], type name]`.
      def signature(node)
        refuse(node, "a signature is `[types] => type`") unless node.is_a?(Prism::KeywordHashNode) && node.elements.size == 1
        pair_signature(node.elements.first)
      end

      def pair_signature(pair)
        refuse(pair.key, "a signature's parameters are an array of types") unless pair.key.is_a?(Prism::ArrayNode)
        [pair.key.elements.map { |t| type_name(t) }, type_name(pair.value)]
      end

      def type_name(node)
        refuse(node, "a type is one of #{TYPES.keys.join(" ")}") unless node.is_a?(Prism::ConstantReadNode) && TYPES.key?(node.name.to_s)
        node.name.to_s
      end

      # A constant's value: an integer, a constant, a struct's size, or an
      # operator over those, folded here.
      def fold(node)
        case node
        when Prism::IntegerNode then node.value
        when Prism::ParenthesesNode then fold(node.body.body.first)
        when Prism::ConstantReadNode
          const_for(node.name.to_s) or refuse(node, "#{node.name} is not a constant here")
        when Prism::CallNode
          if node.receiver.is_a?(Prism::ConstantReadNode) && node.name == :size && (layout = struct_for(node.receiver.name.to_s))
            layout.size
          elsif node.receiver && node.arguments&.arguments&.size == 1 && %i[+ - * << >> | & ^].include?(node.name)
            fold(node.receiver).public_send(node.name, fold(node.arguments.arguments.first))
          else
            refuse(node, "a constant is an integer, a constant, a struct's size, or an operator over those")
          end
        else
          refuse(node, "a constant is an integer, a constant, a struct's size, or an operator over those")
        end
      end

      # `fold` for a def in `file`, so that a refusal gives that file and
      # not the last file declared.
      def fold_in(file, node)
        outer = @file
        @file = file
        fold(node)
      ensure
        @file = outer
      end

      def declare_struct(node)
        name, fields = node.arguments&.arguments
        refuse(node, "a struct is `Machine.struct :Name, field: Type, ...`") unless name.is_a?(Prism::SymbolNode) && fields.is_a?(Prism::KeywordHashNode)
        add_struct(node, name.unescaped)
      end

      # `node` is the call whose last argument has the fields.
      def add_struct(node, name)
        refuse(node, "#{name} is already a struct") if @structs.key?(name)
        refuse(node, "#{name} is already a constant") if @consts.key?(name) || @sigs.key?(name)
        @structs[name] = [node, @file]
      end

      # Each field at its natural alignment; a field of a struct type is
      # embedded in place.
      def layout(name, node)
        fields = node.arguments.arguments.last
        off = 0
        align = 1
        rows = fields.elements.to_h do |pair|
          refuse(pair, "a field is `name: Type`") unless pair.is_a?(Prism::AssocNode) && pair.key.is_a?(Prism::SymbolNode) && pair.value.is_a?(Prism::ConstantReadNode)
          type = pair.value.name.to_s
          size, a = field_shape(pair.value, type)
          off = Bytes.align(off, a)
          align = [align, a].max
          at = off
          off += size
          [pair.key.unescaped, [at, type]]
        end
        size = Bytes.align(off, align)
        Layout.new(name, rows, size, align)
      end

      # `[size, align]` of a field of `type`.
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

      def machine?(node)
        node.is_a?(Prism::ConstantReadNode) && node.name == :Machine
      end

      def libc?(node)
        node.is_a?(Prism::ConstantReadNode) && node.name == :Libc
      end

      # Whether `node` names a `Name = fn ...` signature.
      def sig_read?(node)
        node.is_a?(Prism::ConstantReadNode) && @sigs.key?(node.name.to_s)
      end

      def import_for(name)
        @imports[name]
      end

      def def_for(name)
        @defs[name]
      end

      # The names this unit declares, for a `Description` to read.
      def declared_defs = @defs
      def declared_consts = @consts.keys
      def declared_structs = @structs.keys

      # The file that declares the constant `name`. Only the tests use it
      # (test/unit/os_api_test.rb).
      def const_file(name) = @consts.fetch(name).last

      # A constant's value. It is folded on first use, so a declaration
      # can refer to a constant from a later file.
      def const_for(name)
        resolve(@consts, @const_values, name) { |node| fold(node) }
      end

      def struct_for(name)
        resolve(@structs, @layouts, name) { |node| layout(name, node) }
      end

      def resolve(declared, resolved, name)
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

      # Whether this is a unit of several files. Its refusals give the file.
      def unit?
        @sources.size > 1
      end

      def sig_for(name)
        @sigs[name]
      end

      # A read-only byte string, as a data object of this unit.
      def bytes(string)
        name = "zr_bytes_#{@next_bytes}"
        @next_bytes += 1
        @data << Obj::Datum.new(name, :text_const, string, align: 1)
        name
      end

      # A zeroed, writable area of this unit, one for each name.
      def static(node, name, size)
        if @statics.key?(name)
          refuse(node, "#{name} is #{@statics[name]} bytes, not #{size}") if @statics[name] != size
        else
          @statics[name] = size
          @data << Obj::Datum.new("zr_static_#{name}", :bss, size, align: 16)
        end
        "zr_static_#{name}"
      end

      def refuse(node, message)
        raise Refused.new(node, message, @sources.size > 1 ? @file : nil)
      end
    end
  end
end
