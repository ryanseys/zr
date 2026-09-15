# frozen_string_literal: true

require "prism"
require_relative "../ir"
require_relative "../obj/model"
require_relative "../backend/aarch64/stub"
require_relative "description"

module Ze0
  # The kernel dialect: Ruby syntax, machine semantics. A unit of one or
  # more files holds `Machine.import`, `Machine.struct`, `Machine.sig`
  # and constant declarations, and `sig`-typed `machine def`s, which lower
  # straight to IR, one function per def. Types are `I8 I32 Word Ptr Value
  # F64 Bool Void`; every local takes its type from its first assignment
  # and lives in a frame slot, which `IR::Mem2Reg` turns into values
  # where nothing else takes its address; a call names an import or a def of the same
  # unit, or goes through a pointer with `Machine.call`. A form outside
  # the dialect is refused by name at its line.
  module Machine
    class Refused < StandardError
      attr_reader :line

      def initialize(node, message, file = nil)
        @line = node.location.start_line
        super("#{file ? "#{file}:" : "line "}#{@line}: #{message}")
      end
    end

    # `source` to `[functions, data, raw]`: IR functions, the data objects
    # they name, and the raw functions they call.
    def self.compile(source, file, symbols: Symbols.new)
      Lower.new([[source, file]], symbols).run
    end

    # Several files as one unit: every declaration is visible to every
    # file, in any order, and a def may call a def of any file.
    def self.compile_unit(paths, symbols: Symbols.new)
      unit(paths, symbols: symbols).then { |u| [u.functions, u.data, u.raw] }
    end

    # The compiled unit itself, whose layouts and constants another
    # lowering may read.
    def self.unit(paths, symbols: Symbols.new)
      u = Lower.new(paths.map { |path| [File.read(path), path] }, symbols)
      u.run
      u
    end

    class Lower
      attr_reader :functions, :data, :raw, :symbols

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
      end

      def run
        @sources.each do |source, file|
          result = Prism.parse(source, filepath: file)
          unless result.errors.empty?
            e = result.errors.first
            raise SyntaxError, "#{file}:#{e.location.start_line}: #{e.message}"
          end

          @file = file
          declare(result.value.statements.body)
        end
        @consts.each_key { |name| const_for(name) }
        @structs.each_key { |name| struct_for(name) }
        @defs.each_value { |d| answers_import(d) }
        @collects = collecting_defs
        static(nil, ROOTS, 8) unless @collects.empty?
        @defs.each_value { |d| @functions << Function.new(self, d).lower }
        [@functions, @data, @raw]
      end

      # The static word that heads the chain of kernel root frames.
      ROOTS = "kroots"

      # Whether a call to `name` may run the collector: it is declared
      # with `Machine.collects`, or it reaches one that is, or it calls
      # through a pointer.
      def collects?(name)
        @collects.include?(name)
      end

      # Whether a call to `callee` lowers its body in place rather than a
      # call. A kernel is full of defs one expression long -- a tag test, a
      # static's address, a load off it -- and a call to one costs a frame,
      # its saved registers and a branch each way: more than the body, and
      # the collector makes such calls for every reference it reads.
      #
      # Only a small body that cannot run the collector, and has no
      # `return`, `while` or `break` to mean something else in the caller.
      # The def is still lowered on its own, so its symbol stays for every
      # caller the kernel does not see: an eval, and a `Machine.addr`.
      def inline?(callee)
        return false unless callee.is_a?(Def)

        @inline.fetch(callee.name) do
          @inline[callee.name] = !collects?(callee.name) && callee.node.body && small?(callee.node.body, [INLINE_NODES])
        end
      end

      # Prism nodes an inlined body may have, at most.
      INLINE_NODES = 32

      def small?(node, budget)
        budget[0] -= 1
        return false if budget[0].negative?
        return false if node.is_a?(Prism::ReturnNode) || node.is_a?(Prism::WhileNode) || node.is_a?(Prism::BreakNode)

        node.compact_child_nodes.all? { |c| small?(c, budget) }
      end

      # The defs that may run the collector, by fixpoint over the calls
      # each body makes.
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
          elsif node.name == :call && machine?(node.receiver)
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
            name = node.name.to_s
            refuse(node, "#{name} is already a constant") if @consts.key?(name)
            refuse(node, "#{name} is already a struct") if @structs.key?(name)
            @consts[name] = [node.value, @file]
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
              params, ret = signature(sig)
              @sigs[name.unescaped] = Signature.new(name.unescaped, params, ret)
            else
              refuse(node, "a sig is `sig [types] => type`") unless node.receiver.nil?
              pending_sig = signature(node.arguments.arguments.first)
            end
          when :import
            refuse(node, "an import is `Machine.import \"name\", [types] => type`") unless machine?(node.receiver)
            name, sig = node.arguments.arguments
            params, ret, from = import_signature(sig)
            @imports[name.unescaped] = Import.new(name.unescaped, params, ret, from)
          when :collects
            refuse(node, "`Machine.collects` takes the symbol of a machine def") unless machine?(node.receiver) && node.arguments&.arguments&.first.is_a?(Prism::SymbolNode)
            @collectors << node.arguments.arguments.first.unescaped
          when :raw
            refuse(node, "a raw function is `Machine.raw \"name\"`") unless machine?(node.receiver)
            name = node.arguments.arguments.first.unescaped
            params, ret = Backend::Aarch64::Stub::ALL.fetch(name) { refuse(node, "no raw function named #{name}") }
            @imports[name] = Raw.new(name, params.map(&:to_s), ret.to_s)
            @raw << Backend::Aarch64::Stub.public_send(name.delete_prefix("zr_"))
          when :machine
            d = node.arguments&.arguments&.first
            refuse(node, "`machine` takes a def") unless d.is_a?(Prism::DefNode)
            refuse(d, "a machine def has no sig ahead of it") if pending_sig.nil?
            params, ret = pending_sig
            pending_sig = nil
            refuse(d, "a machine def's name is letters, digits and underscores") unless d.name.to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
            names = (d.parameters&.requireds || []).map { |p| p.name.to_s }
            refuse(d, "the sig has #{params.size} types for #{names.size} parameters") if names.size != params.size
            refuse(d, "a machine def takes required parameters only") if d.parameters && d.parameters.child_nodes.compact.size != names.size
            refuse(d, "#{d.name} is defined twice; the first is in #{@defs[d.name.to_s].file}") if @defs.key?(d.name.to_s)
            @defs[d.name.to_s] = Def.new(d.name.to_s, names.zip(params), ret, d, @file)
          else
            refuse(node, "`#{node.name}` is not in the kernel dialect at the top level")
          end
        end
      end

      # An import's `[[type names], type name, module]`: `from:`, which
      # names the wasm module it comes from, is one more pair of the same
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

      # A def of an imported name answers that import's calls in its
      # place: an OS layer defines the libc call its OS does not have. It
      # takes the import's signature, or a call written for one would
      # pass the other.
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

      # `fold` for a def in `file`, so that a refusal names that file and
      # not the last one declared.
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
        refuse(node, "#{name.unescaped} is already a struct") if @structs.key?(name.unescaped)
        refuse(node, "#{name.unescaped} is already a constant") if @consts.key?(name.unescaped)
        @structs[name.unescaped] = [node, @file]
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
          off = (off + a - 1) & ~(a - 1)
          align = [align, a].max
          at = off
          off += size
          [pair.key.unescaped, [at, type]]
        end
        size = (off + align - 1) & ~(align - 1)
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

      # The file that declares the constant `name`.
      def const_file(name) = @consts.fetch(name).last

      # A constant's value, folded on first use so a declaration may name
      # one from a later file.
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

      # Whether this is a unit of several files, whose refusals name the file.
      def unit?
        @sources.size > 1
      end

      def sig_for(name)
        @sigs[name]
      end

      # A read-only byte string, as a data object this unit carries.
      def bytes(string)
        name = "zr_bytes_#{@next_bytes}"
        @next_bytes += 1
        @data << Obj::Data.new(name, :text_const, string, align: 1)
        name
      end

      # A zeroed, writable area this unit carries, one per name.
      def static(node, name, size)
        if @statics.key?(name)
          refuse(node, "#{name} is #{@statics[name]} bytes, not #{size}") if @statics[name] != size
        else
          @statics[name] = size
          @data << Obj::Data.new("zr_static_#{name}", :bss, size, align: 16)
        end
        "zr_static_#{name}"
      end

      def refuse(node, message)
        raise Refused.new(node, message, @sources.size > 1 ? @file : nil)
      end
    end

    # One machine def to one IR function. A def that may run the
    # collector keeps a root frame in its frame: `prev, n, values...`,
    # linked from the unit's static head, holding every Value it has (a
    # parameter, a local, or a call's answer passed on to another call),
    # so a collection under any call it makes sees them all.
    class Function
      def initialize(unit, d)
        @unit = unit
        @d = d
        @f = IR::Function.new(d.name, d.params.map { |_, t| TYPES.fetch(t) }, TYPES.fetch(d.ret))
        @locals = {}
        @loops = []
        @roots = nil
        @inlining = [d.name]
      end

      def lower
        enter_roots if @unit.collects?(@d.name)
        @d.params.each_with_index do |(name, type), i|
          local = declare_local(@d.node, name, type)
          @f.store(@f.args[i], local[:addr])
        end
        body = @d.node.body
        value, type = body ? statements(body, @d.ret) : [nil, "Void"]
        unless @f.terminated?
          refuse(@d.node, "the body ends in #{type}, and the sig says #{@d.ret}") unless @d.ret == "Void" || fits?(@d.ret, type)
          ret(@d.ret == "Void" ? nil : value)
        end
        leave_roots if @roots
        IR::Mem2Reg.run(@f)
      end

      # The root frame: linked in ahead of the body, its slot count and
      # zero fill filled in once the body has asked for every slot.
      def enter_roots
        slot = @f.slot(16)
        @roots = { slot: slot, addr: @f.stack_addr(slot), n: 0, zero: @f.iconst("i64", 0) }
        @head = @f.symbol_value(@f.symbol("zr_static_#{Lower::ROOTS}"))
        @f.store(@f.fetch("i64", @head), @roots[:addr], 0)
        count, @roots[:count] = @f.iconst_later("i64")
        @f.store(count, @roots[:addr], 8)
        @f.store(@roots[:addr], @head, 0)
        @roots[:fill_at] = @f.entry_block.insts.size
      end

      def leave_roots
        n = @roots[:n]
        @roots[:count].args[0] = n
        @f.slots[@roots[:slot].delete_prefix("ss").to_i].bytes = 16 + (8 * n)
        fill = (0...n).map { |i| IR::Inst.new(:store, args: [@roots[:zero], @roots[:addr]], offset: 16 + (8 * i), flags: "notrap aligned") }
        @f.entry_block.insts.insert(@roots[:fill_at], *fill)
      end

      # A fresh root slot's address and offset.
      def root_slot
        at = 16 + (8 * @roots[:n])
        @roots[:n] += 1
        at
      end

      # `return`: the root frame is unlinked first.
      def ret(value)
        @f.store(@f.fetch("i64", @roots[:addr]), @head, 0) if @roots
        @f.ret(value)
      end

      private

      def refuse(node, message)
        raise Refused.new(node, message, @unit.unit? ? @d.file : nil)
      end

      # A local lives in a slot of its own; a Value in a rooted function
      # lives in the root frame.
      def declare_local(node, name, type)
        refuse(node, "#{name} is already a #{@locals[name][:type]}") if @locals.key?(name) && !fits?(@locals[name][:type], type)
        @locals[name] ||= { type: type, addr: local_addr(type) }
      end

      def local_addr(type)
        return @f.stack_addr(@f.slot(8)) unless @roots && type == "Value"

        at = root_slot
        off = @f.iconst("i64", at)
        @f.hoisted(:root_slot, at) { IR::Inst.new(:iadd, type: "i64", args: [@roots[:addr], off]) }
      end

      # The IR type a kernel type lowers to.
      def ir_type(type)
        TYPES.fetch(type)
      end

      # The value and type of a statement list: the last statement's,
      # which is the one `want` applies to.
      def statements(node, want = nil)
        last = [nil, "Void"]
        node.body.each_with_index do |s, i|
          last = expr(s, i == node.body.size - 1 ? want : nil)
          break if @f.terminated?
        end
        last
      end

      # `[value, type]`; `want` names the type a literal takes here.
      def expr(node, want = nil)
        case node
        when Prism::StatementsNode then statements(node, want)
        when Prism::ParenthesesNode then node.body ? statements(node.body, want) : [nil, "Void"]
        when Prism::IntegerNode then literal(node, node.value, want)
        when Prism::ConstantReadNode
          value = @unit.const_for(node.name.to_s) or refuse(node, "#{node.name} is not a constant here")
          literal(node, value, want)
        when Prism::AndNode then logical(node, :and)
        when Prism::OrNode then logical(node, :or)
        when Prism::TrueNode then [@f.iconst("i8", 1), "Bool"]
        when Prism::FalseNode then [@f.iconst("i8", 0), "Bool"]
        when Prism::NilNode then [nil, "Void"]
        when Prism::LocalVariableReadNode
          local = @locals[node.name.to_s] or refuse(node, "#{node.name} is read before it is assigned")
          [@f.fetch(ir_type(local[:type]), local[:addr]), local[:type]]
        when Prism::LocalVariableWriteNode
          value, type = expr(node.value, @locals.dig(node.name.to_s, :type))
          refuse(node, "#{node.name} is assigned nothing") if type == "Void"
          local = declare_local(node, node.name.to_s, type)
          @f.store(value, local[:addr])
          [value, type]
        when Prism::LocalVariableOperatorWriteNode
          local = @locals[node.name.to_s] or refuse(node, "#{node.name} is read before it is assigned")
          current = @f.fetch(ir_type(local[:type]), local[:addr])
          rhs, = expr(node.value, local[:type])
          value, type = binary(node, node.binary_operator, current, local[:type], rhs, local[:type])
          @f.store(value, local[:addr])
          [value, type]
        when Prism::CallNode then call(node, want)
        when Prism::IfNode
          branch(node, want, node.statements, node.subsequent.is_a?(Prism::ElseNode) ? node.subsequent.statements : node.subsequent)
        when Prism::UnlessNode then branch(node, want, node.else_clause&.statements, node.statements)
        when Prism::WhileNode then loop_while(node)
        when Prism::BreakNode
          refuse(node, "a break outside a while") if @loops.empty?
          refuse(node, "a break with a value") if node.arguments
          @f.jump(@loops.last)
          [nil, "Void"]
        when Prism::ReturnNode
          value, type = node.arguments ? expr(node.arguments.arguments.first, @d.ret) : [nil, "Void"]
          refuse(node, "a return of #{type} from a def whose sig says #{@d.ret}") unless fits?(@d.ret, type)
          ret(type == "Void" ? nil : value)
          [nil, "Void"]
        else
          refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not in the kernel dialect")
        end
      end

      # A size or an offset: an integer, a constant, or an operator over
      # those, folded at compile time.
      def immediate(node)
        @unit.fold_in(@d.file, node)
      end

      # An integer literal, or a constant, takes the type wanted here.
      def literal(node, n, want)
        type = want || "Word"
        refuse(node, "an integer where a #{type} is wanted") if ir_type(type).nil? || ir_type(type) == "f64"
        [@f.iconst(ir_type(type), n), type]
      end

      def call(node, want)
        args = node.arguments&.arguments || []
        if node.receiver.nil?
          target(node, node.name.to_s, args)
        elsif @unit.machine?(node.receiver)
          intrinsic(node, args, want)
        elsif node.name == :! && args.empty?
          value, type = condition_value(node.receiver)
          [@f.icmp("eq", value, @f.iconst(ir_type(type), 0)), "Bool"]
        elsif node.name == :-@ && args.empty?
          value, type = expr(node.receiver, want)
          return [@f.funop(:fneg, value), type] if type == "F64"

          refuse(node, "a negation of a #{type}") unless ir_type(type)
          [@f.isub(@f.iconst(ir_type(type), 0), value), type]
        elsif node.receiver.is_a?(Prism::ConstantReadNode) && (layout = @unit.struct_for(node.receiver.name.to_s))
          field(node, layout, args, want)
        elsif args.size == 1 && OPERATORS.key?(node.name)
          lhs, lt = expr(node.receiver, want)
          rhs, rt = expr(args.first, lt)
          binary(node, node.name, lhs, lt, rhs, rt)
        else
          refuse(node, "a call with a receiver that is not Machine or a struct")
        end
      end

      # `Name.size`, `Name.field(p)` and `Name.set_field(p, v)`; a field
      # of a struct type answers its address.
      def field(node, layout, args, want)
        name = node.name.to_s
        return literal(node, layout.size, want) if name == "size" && args.empty?

        writer = name.start_with?("set_")
        fname = writer ? name.delete_prefix("set_") : name
        off, type = layout.fields.fetch(fname) { refuse(node, "#{layout.name} has no field #{fname}") }
        refuse(node, "#{layout.name}.#{name} takes #{writer ? "a pointer and a value" : "a pointer"}") if args.size != (writer ? 2 : 1)
        ptr, pt = expr(args[0])
        refuse(args[0], "#{layout.name}.#{name} of a #{pt}") unless %w[Ptr Word Value].include?(pt)
        if @unit.struct_for(type)
          refuse(node, "#{fname} is a #{type}; set its fields instead") if writer
          [off.zero? ? ptr : @f.iadd(ptr, @f.iconst("i64", off)), "Ptr"]
        elsif writer
          value, vt = expr(args[1], type)
          refuse(args[1], "#{layout.name}.#{fname} is a #{type}, not a #{vt}") unless ir_type(vt) == ir_type(type)
          @f.store(value, ptr, off)
          [nil, "Void"]
        else
          [@f.fetch(ir_type(type), ptr, off), type]
        end
      end

      # `a && b` and `a || b`, the right side lowered only when the left
      # decides nothing; the result is a Bool.
      #
      # A right side that is `plain?` is lowered either way, and the two
      # bits are joined with no branch at all: reading it can change
      # nothing and fault on nothing, so reading it when the left side
      # already decided is not observable. `zr_special_p` is three such
      # tests, the collector asks it of every reference, and as a diamond
      # of blocks each test cost a compare, two sets, three widenings and
      # a branch.
      def logical(node, op)
        bit = truth(*condition_value(node.left))
        if plain?(node.right)
          other = truth(*condition_value(node.right))
          return [@f.binop(op == :and ? :band : :bor, bit, other), "Bool"]
        end

        rest = @f.label
        skip = @f.label
        merge, params = @f.block(["i8"])
        op == :and ? @f.brif(bit, rest, skip) : @f.brif(bit, skip, rest)
        @f.switch(skip)
        @f.jump(merge, [bit])
        @f.switch(rest)
        @f.jump(merge, [truth(*condition_value(node.right))])
        @f.switch(merge)
        [params.first, "Bool"]
      end

      # `value` as a Bool: one already is, being 0 or 1, and any other
      # integer is true when it is not zero.
      def truth(value, type)
        type == "Bool" ? value : @f.icmp("ne", value, @f.iconst(ir_type(type), 0))
      end

      # Operators whose lowering is one instruction over its operands, with
      # no effect, and no fault whatever the operands hold. Division is not
      # among them.
      PLAIN_OPERATORS = %i[+ - * & | ^ << >> < <= > >= == != !].freeze
      PLAIN_CASTS = %i[i32 i8 word sword ptr value].freeze

      # Whether `node` reads only literals, constants and locals, through
      # plain operators and casts: an expression whose value is all its
      # lowering makes. A local sits in the frame, so reading it is safe
      # on any path; a load through a pointer is not.
      def plain?(node)
        case node
        when Prism::IntegerNode, Prism::TrueNode, Prism::FalseNode, Prism::ConstantReadNode then true
        when Prism::LocalVariableReadNode then @locals.key?(node.name.to_s)
        when Prism::ParenthesesNode then node.body.is_a?(Prism::StatementsNode) && node.body.body.one? && plain?(node.body.body[0])
        when Prism::AndNode, Prism::OrNode then plain?(node.left) && plain?(node.right)
        when Prism::CallNode
          args = node.arguments&.arguments || []
          return false if node.block || node.receiver.nil?
          return PLAIN_CASTS.include?(node.name) && args.one? && plain?(args[0]) if @unit.machine?(node.receiver)

          PLAIN_OPERATORS.include?(node.name) && args.size <= 1 && plain?(node.receiver) && args.all? { |a| plain?(a) }
        else false
        end
      end

      OPERATORS = {
        :+ => "iadd", :- => "isub", :* => "imul", :& => "band", :| => "bor", :^ => "bxor", :<< => "ishl",
        :< => "lt", :<= => "le", :> => "gt", :>= => "ge", :== => "eq", :!= => "ne",
        :/ => nil, :% => nil, :>> => nil
      }.freeze

      # Word and Ptr mix: a Ptr plus or minus a Word is a Ptr, a Ptr minus
      # a Ptr is a Word, and a comparison with a Ptr on either side is
      # unsigned. Value never mixes.
      def binary(node, op, lhs, lt, rhs, rt)
        refuse(node, "#{op} on #{lt} and #{rt}") unless ir_type(lt) && (lt == rt || (PLAIN.include?(lt) && PLAIN.include?(rt)))
        return float_binary(node, op, lhs, rhs) if lt == "F64"

        ptr = lt == "Ptr" || rt == "Ptr"
        result = if ptr && op == :- && lt == rt then "Word"
                 elsif ptr then "Ptr"
                 else lt
                 end
        case op
        when :+, :-, :*, :&, :|, :^, :<<
          [@f.binop(OPERATORS[op].to_sym, lhs, rhs), result]
        when :/, :%, :>>
          mnemonic = { :/ => "div", :% => "rem", :>> => "shr" }[op]
          [@f.binop(:"#{ptr ? "u" : "s"}#{mnemonic}", lhs, rhs), result]
        when :==, :!=
          [@f.icmp(OPERATORS[op], lhs, rhs), "Bool"]
        when :<, :<=, :>, :>=
          cond = (ptr ? "u" : "s") + OPERATORS[op]
          [@f.icmp(cond, lhs, rhs), "Bool"]
        else
          refuse(node, "#{op} is not in the kernel dialect")
        end
      end

      FLOAT_OPS = { :+ => :fadd, :- => :fsub, :* => :fmul, :/ => :fdiv }.freeze
      FLOAT_CONDS = { :== => "eq", :!= => "ne", :< => "lt", :<= => "le", :> => "gt", :>= => "ge" }.freeze

      # F64 arithmetic and comparison; a comparison with NaN on either
      # side is false, except `!=`.
      def float_binary(node, op, lhs, rhs)
        return [@f.fbinop(FLOAT_OPS[op], lhs, rhs), "F64"] if FLOAT_OPS.key?(op)
        return [@f.fcmp(FLOAT_CONDS[op], lhs, rhs), "Bool"] if FLOAT_CONDS.key?(op)

        refuse(node, "#{op} on an F64")
      end

      PLAIN = %w[Word Ptr].freeze

      def fits?(want, got)
        want == got || (PLAIN.include?(want) && PLAIN.include?(got))
      end

      # A call to an import or to a def of this file.
      def target(node, name, args)
        callee = @unit.def_for(name) || @unit.import_for(name) or refuse(node, "#{name} is not an import or a machine def here")
        refuse(node, "#{name} takes #{callee.params.size} arguments, not #{args.size}") if args.size != callee.params.size
        types = callee.is_a?(Def) ? callee.params.map(&:last) : callee.params
        values = args.zip(types).map do |arg, type|
          value, got = expr(arg, type)
          refuse(arg, "#{name} wants a #{type} here, not a #{got}") unless fits?(type, got)
          rooted(arg, value, got)
        end
        return inline(callee, values) if @unit.inline?(callee) && !@inlining.include?(callee.name)

        from = callee.from if callee.is_a?(Import)
        fn = @f.callee(name, types.map { |t| ir_type(t) }, ir_type(callee.ret), colocated: !callee.is_a?(Import), from: from)
        if callee.ret == "Void"
          @f.call(fn, values)
          [nil, "Void"]
        else
          [@f.call_val(fn, values), callee.ret]
        end
      end

      # `d`'s body where the call stands, over the argument `values`: its
      # parameters and locals in a scope of their own, as the call would
      # have had. Refusals inside name the callee's file.
      #
      # The body cannot collect, so nothing in it goes in the root frame:
      # a Value there lives in a slot of its own, as the call would have
      # kept it, and `IR::Mem2Reg` can make it a register.
      def inline(d, values)
        outer = [@locals, @d, @roots]
        @locals = {}
        @d = d
        @roots = nil
        @inlining << d.name
        d.params.each_with_index do |(name, type), i|
          @f.store(values[i], declare_local(d.node, name, type)[:addr])
        end
        value, type = d.node.body ? statements(d.node.body, d.ret) : [nil, "Void"]
        refuse(d.node, "the body ends in #{type}, and the sig says #{d.ret}") unless d.ret == "Void" || fits?(d.ret, type)
        d.ret == "Void" ? [nil, "Void"] : [value, d.ret]
      ensure
        @inlining.pop
        @locals, @d, @roots = outer
      end

      # A Value a call answered stays alive across the calls that follow
      # it in the same argument list: it gets a root slot of its own.
      def rooted(node, value, type)
        return value unless @roots && type == "Value" && node.is_a?(Prism::CallNode) && node.receiver.nil?

        @f.store(value, @roots[:addr], root_slot)
        value
      end

      def intrinsic(node, args, want)
        case node.name
        when :id
          name = args.first
          refuse(node, "Machine.id takes a symbol") unless name.is_a?(Prism::SymbolNode) && args.size == 1
          literal(node, @unit.symbols.id(name.unescaped), want)
        when :bytesize
          s = args.first
          refuse(node, "Machine.bytesize takes a string literal") unless s.is_a?(Prism::StringNode)
          literal(node, s.unescaped.bytesize, want)
        when :extern
          name = args.first
          refuse(node, "Machine.extern takes the symbol of a data object another unit defines") unless name.is_a?(Prism::SymbolNode)
          [@f.symbol_value(@f.symbol(name.unescaped, colocated: false)), "Ptr"]
        when :call
          name = args.first
          refuse(node, "Machine.call takes the name of a Machine.sig, a pointer and the arguments") unless name.is_a?(Prism::SymbolNode)
          s = @unit.sig_for(name.unescaped) or refuse(node, "#{name.unescaped} is not a Machine.sig here")
          ptr, pt = expr(args[1] || refuse(node, "Machine.call takes a pointer after the signature"), "Ptr")
          refuse(args[1], "Machine.call through a #{pt}") unless fits?("Ptr", pt)
          rest = args[2..]
          refuse(node, "#{name.unescaped} takes #{s.params.size} arguments, not #{rest.size}") if rest.size != s.params.size
          values = rest.zip(s.params).map do |arg, type|
            value, got = expr(arg, type)
            refuse(arg, "#{name.unescaped} wants a #{type} here, not a #{got}") unless fits?(type, got)
            rooted(arg, value, got)
          end
          sig = @f.sig(s.params.map { |t| ir_type(t) }, ir_type(s.ret))
          return [@f.call_indirect(sig, ptr, values), "Void"] if s.ret == "Void"

          [@f.call_indirect_val(sig, ptr, values), s.ret]
        when :bytes
          s = args.first
          refuse(node, "Machine.bytes takes a string literal") unless s.is_a?(Prism::StringNode)
          [@f.symbol_value(@f.symbol(@unit.bytes(s.unescaped))), "Ptr"]
        when :load64, :load32, :load8
          width = { load64: "i64", load32: "i32", load8: "i8" }[node.name]
          ptr, pt = expr(args[0], "Ptr")
          refuse(node, "#{node.name} takes a Ptr and an offset") unless fits?("Ptr", pt) && args.size == 2
          type = { load64: "Word", load32: "I32", load8: "I8" }[node.name]
          [@f.fetch(width, ptr, immediate(args[1])), type]
        when :store64, :store32, :store8
          ptr, pt = expr(args[0], "Ptr")
          refuse(node, "#{node.name} takes a Ptr, an offset and a value") unless fits?("Ptr", pt) && args.size == 3
          type = { store64: "Word", store32: "I32", store8: "I8" }[node.name]
          value, vt = expr(args[2], type)
          refuse(node, "#{node.name} stores a #{type}, not a #{vt}") unless ir_type(vt) == ir_type(type)
          @f.store(value, ptr, immediate(args[1]))
          [nil, "Void"]
        when :slot
          refuse(node, "Machine.slot takes a size") unless args.size == 1
          [@f.stack_addr(@f.slot(immediate(args.first))), "Ptr"]
        when :static
          name, size = args
          refuse(node, "Machine.static takes a symbol and a size") unless name.is_a?(Prism::SymbolNode) && size
          [@f.symbol_value(@f.symbol(@unit.static(node, name.unescaped, immediate(size)))), "Ptr"]
        when :i32, :i8, :word, :sword, :ptr, :value
          value, type = expr(args.first)
          convert(node, node.name, value, type)
        when :f64, :bits, :to_f64, :to_int
          value, type = expr(args.first)
          float_convert(node, node.name, value, type)
        when :sqrt, :floor, :ceil, :trunc, :nearest, :fabs
          value, type = expr(args.first)
          refuse(node, "Machine.#{node.name} of a #{type}") unless type == "F64"
          [@f.funop(node.name, value), "F64"]
        when :addr
          name = args.first
          refuse(node, "Machine.addr takes the symbol of a machine def") unless name.is_a?(Prism::SymbolNode)
          d = @unit.def_for(name.unescaped) or refuse(node, "#{name.unescaped} is not a machine def here")
          fn = @f.callee(d.name, d.params.map { |_, t| ir_type(t) }, ir_type(d.ret), colocated: true)
          [@f.func_addr(fn), "Ptr"]
        else
          refuse(node, "Machine.#{node.name} is not an intrinsic")
        end
      end

      # A width or a reading change: `Machine.i32(x)` narrows, `word`
      # zero-extends, `sword` sign-extends, `ptr`/`value`/`word` between
      # 64-bit types is only a reading.
      def convert(node, to, value, type)
        target = { i32: "I32", i8: "I8", word: "Word", sword: "Word", ptr: "Ptr", value: "Value" }[to]
        from, into = ir_type(type), ir_type(target)
        refuse(node, "Machine.#{to} of a #{type}") if from.nil? || from == "f64"
        return [value, target] if from == into
        return [@f.ireduce(into, value), target] if from == "i64" || (from == "i32" && into == "i8")

        [to == :sword ? @f.sextend(into, value) : @f.uextend(into, value), target]
      end

      # `Machine.f64(word)` and `Machine.bits(f)` read the same 64 bits
      # as the other type; `to_f64` and `to_int` convert by value, the
      # latter saturating.
      def float_convert(node, to, value, type)
        case to
        when :f64
          refuse(node, "Machine.f64 of a #{type}") unless %w[Word Ptr Value].include?(type)
          [@f.bitcast("f64", value), "F64"]
        when :bits
          refuse(node, "Machine.bits of a #{type}") unless type == "F64"
          [@f.bitcast("i64", value), "Word"]
        when :to_f64
          refuse(node, "Machine.to_f64 of a #{type}") unless %w[Word Ptr Value].include?(type)
          [@f.fcvt_from_sint(value), "F64"]
        when :to_int
          refuse(node, "Machine.to_int of a #{type}") unless type == "F64"
          [@f.fcvt_to_sint_sat(value), "Word"]
        end
      end

      def condition(node)
        condition_value(node.predicate).first
      end

      # `[value, type]` of an expression a branch may test: any integer.
      def condition_value(node)
        value, type = expr(node)
        refuse(node, "a condition that is a #{type}") unless %w[Bool I8 I32 Word Ptr Value].include?(type)
        [value, type]
      end

      # `if` as a value when both arms agree on a type, else Void. Each arm
      # is lowered before the merge block's shape is known, so the arms'
      # jumps are written last. `then_stmts` is the then arm; `else_part`
      # is the else arm's statements, an elsif, or nil.
      def branch(node, want, then_stmts, else_part)
        cond = condition(node)
        then_b = @f.label
        else_b = @f.label
        @f.brif(cond, then_b, else_b)
        @f.switch(then_b)
        tv, tt = then_stmts ? statements(then_stmts, want) : [nil, "Void"]
        then_open = !@f.terminated?
        then_end = @f.current.name
        @f.switch(else_b, open: true)
        ev, et = else_part ? expr(else_part, want) : [nil, "Void"]
        else_open = !@f.terminated?
        else_end = @f.current.name
        return [nil, "Void"] if !then_open && !else_open

        joined = then_open && else_open && tt == et && tt != "Void" ? tt : "Void"
        merge, params = joined == "Void" ? @f.block : @f.block([ir_type(joined)])
        carry = joined == "Void" ? [] : nil
        @f.finish(then_end, IR::Inst.new(:jump, targets: [[merge, carry || [tv]]])) if then_open
        @f.finish(else_end, IR::Inst.new(:jump, targets: [[merge, carry || [ev]]])) if else_open
        @f.switch(merge, open: true)
        [joined == "Void" ? nil : params.first, joined]
      end

      def loop_while(node)
        head = @f.label
        body = @f.label
        done = @f.label
        @f.jump(head)
        @f.switch(head)
        cond = condition(node)
        @f.brif(cond, body, done)
        @f.switch(body)
        @loops.push(done)
        statements(node.statements) if node.statements
        @loops.pop
        @f.jump(head) unless @f.terminated?
        @f.switch(done)
        [nil, "Void"]
      end
    end
  end
end
