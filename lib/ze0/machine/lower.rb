# frozen_string_literal: true

require "prism"
require_relative "../ir"
require_relative "../obj/model"
require_relative "stub"

module Ze0
  # The kernel dialect: Ruby syntax, machine semantics. A unit of one or
  # more files holds `Machine.import`, `Machine.struct`, `Machine.sig`
  # and constant declarations, and `sig`-typed `machine def`s, which lower
  # straight to IR, one function per def. Types are `I8 I32 Word Ptr Value
  # F64 Bool Void`; every local takes its type from its first assignment
  # and lives in a frame slot; a call names an import or a def of the same
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

    TYPES = {
      "I8" => "i8", "Bool" => "i8", "I32" => "i32", "Word" => "i64", "Ptr" => "i64",
      "Value" => "i64", "F64" => "f64", "Void" => nil
    }.freeze
    # Comparisons that read their operands as unsigned: pointers.
    UNSIGNED = %w[Ptr].freeze

    Import = Struct.new(:name, :params, :ret)
    Def = Struct.new(:name, :params, :ret, :node, :file)
    # A function delivered as machine code: `Machine.raw "zr_switch"`.
    Raw = Struct.new(:name, :params, :ret)
    # A signature `Machine.call` goes through: `Machine.sig :name, [types] => type`.
    Signature = Struct.new(:name, :params, :ret)
    # `Machine.struct :Name, field: Type, ...`: fields as `name => [offset, type]`.
    Layout = Struct.new(:name, :fields, :size, :align)

    # The symbol ids a unit names with `Machine.id(:name)`: the compiler
    # owns the table, and a unit compiled alone numbers names as it meets
    # them.
    class Symbols
      attr_reader :ids

      def initialize(names = [])
        @ids = {}
        names.each { |n| id(n) }
      end

      def id(name)
        @ids[name.to_s] ||= @ids.size
      end
    end

    # `source` to `[functions, data, raw]`: IR functions, the data objects
    # they name, and the raw functions they call.
    def self.compile(source, file, symbols: Symbols.new)
      Lower.new([[source, file]], symbols).run
    end

    # Several files as one unit: every declaration is visible to every
    # file after it, and a def may call a def of any file.
    def self.compile_unit(paths, symbols: Symbols.new)
      Lower.new(paths.map { |path| [File.read(path), path] }, symbols).run
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
        @sigs = {}
        @functions = []
        @data = []
        @raw = []
        @next_bytes = 0
        @statics = {}
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
        @defs.each_value { |d| @functions << Function.new(self, d).lower }
        [@functions, @data, @raw]
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
            @consts[name] = fold(node.value)
            next
          end
          refuse(node, "a statement that is not a declaration or a machine def") unless node.is_a?(Prism::CallNode)
          case node.name
          when :struct
            refuse(node, "a struct is `Machine.struct :Name, field: Type, ...`") unless machine?(node.receiver)
            layout(node)
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
            params, ret = signature(sig)
            @imports[name.unescaped] = Import.new(name.unescaped, params, ret)
          when :raw
            refuse(node, "a raw function is `Machine.raw \"name\"`") unless machine?(node.receiver)
            name = node.arguments.arguments.first.unescaped
            params, ret = Stub::ALL.fetch(name) { refuse(node, "no raw function named #{name}") }
            @imports[name] = Raw.new(name, params.map(&:to_s), ret.to_s)
            @raw << Stub.public_send(name.delete_prefix("zr_"))
          when :machine
            d = node.arguments&.arguments&.first
            refuse(node, "`machine` takes a def") unless d.is_a?(Prism::DefNode)
            refuse(d, "a machine def has no sig ahead of it") if pending_sig.nil?
            params, ret = pending_sig
            pending_sig = nil
            names = (d.parameters&.requireds || []).map { |p| p.name.to_s }
            refuse(d, "the sig has #{params.size} types for #{names.size} parameters") if names.size != params.size
            refuse(d, "a machine def takes required parameters only") if d.parameters && d.parameters.child_nodes.compact.size != names.size
            @defs[d.name.to_s] = Def.new(d.name.to_s, names.zip(params), ret, d, @file)
          else
            refuse(node, "`#{node.name}` is not in the kernel dialect at the top level")
          end
        end
      end

      # `[types] => type` as `[[type names], type name]`.
      def signature(node)
        refuse(node, "a signature is `[types] => type`") unless node.is_a?(Prism::KeywordHashNode) && node.elements.size == 1
        pair = node.elements.first
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
          @consts.fetch(node.name.to_s) { refuse(node, "#{node.name} is not a constant here") }
        when Prism::CallNode
          if node.receiver.is_a?(Prism::ConstantReadNode) && @structs.key?(node.receiver.name.to_s) && node.name == :size
            @structs[node.receiver.name.to_s].size
          elsif node.receiver && node.arguments&.arguments&.size == 1 && %i[+ - * << >> | & ^].include?(node.name)
            fold(node.receiver).public_send(node.name, fold(node.arguments.arguments.first))
          else
            refuse(node, "a constant is an integer, a constant, a struct's size, or an operator over those")
          end
        else
          refuse(node, "a constant is an integer, a constant, a struct's size, or an operator over those")
        end
      end

      # Each field at its natural alignment; a field of a struct type is
      # embedded in place.
      def layout(node)
        name, fields = node.arguments&.arguments
        refuse(node, "a struct is `Machine.struct :Name, field: Type, ...`") unless name.is_a?(Prism::SymbolNode) && fields.is_a?(Prism::KeywordHashNode)
        refuse(node, "#{name.unescaped} is already a struct") if @structs.key?(name.unescaped)
        refuse(node, "#{name.unescaped} is already a constant") if @consts.key?(name.unescaped)
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
        @structs[name.unescaped] = Layout.new(name.unescaped, rows, size, align)
      end

      # `[size, align]` of a field of `type`.
      def field_shape(node, type)
        return [@structs[type].size, @structs[type].align] if @structs.key?(type)

        case TYPES.fetch(type) { refuse(node, "a field's type is a type or a struct declared above it") }
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

      def const_for(name)
        @consts[name]
      end

      # Whether this is a unit of several files, whose refusals name the file.
      def unit?
        @sources.size > 1
      end

      def struct_for(name)
        @structs[name]
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

    # One machine def to one IR function.
    class Function
      def initialize(unit, d)
        @unit = unit
        @d = d
        @f = IR::Function.new(d.name, d.params.map { |_, t| TYPES.fetch(t) }, TYPES.fetch(d.ret))
        @locals = {}
      end

      def lower
        @d.params.each_with_index do |(name, type), i|
          local = declare_local(@d.node, name, type)
          @f.ins "store notrap aligned #{@f.args[i]}, #{local[:addr]}"
        end
        body = @d.node.body
        value, type = body ? statements(body, @d.ret) : [nil, "Void"]
        return @f if @f.terminated?

        if @d.ret == "Void"
          @f.ins "return"
        else
          refuse(@d.node, "the body ends in #{type}, and the sig says #{@d.ret}") unless fits?(@d.ret, type)
          @f.ins "return #{value}"
        end
        @f
      end

      private

      def refuse(node, message)
        raise Refused.new(node, message, @unit.unit? ? @d.file : nil)
      end

      def declare_local(node, name, type)
        refuse(node, "#{name} is already a #{@locals[name][:type]}") if @locals.key?(name) && !fits?(@locals[name][:type], type)
        @locals[name] ||= { type: type, addr: @f.stack_addr(@f.slot(8)) }
      end

      def clif(type)
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
          [@f.val("load.#{clif(local[:type])} notrap aligned #{local[:addr]}"), local[:type]]
        when Prism::LocalVariableWriteNode
          value, type = expr(node.value, @locals.dig(node.name.to_s, :type))
          refuse(node, "#{node.name} is assigned nothing") if type == "Void"
          local = declare_local(node, node.name.to_s, type)
          @f.ins "store notrap aligned #{value}, #{local[:addr]}"
          [value, type]
        when Prism::LocalVariableOperatorWriteNode
          local = @locals[node.name.to_s] or refuse(node, "#{node.name} is read before it is assigned")
          current = @f.val("load.#{clif(local[:type])} notrap aligned #{local[:addr]}")
          rhs, = expr(node.value, local[:type])
          value, type = binary(node, node.binary_operator, current, local[:type], rhs, local[:type])
          @f.ins "store notrap aligned #{value}, #{local[:addr]}"
          [value, type]
        when Prism::CallNode then call(node, want)
        when Prism::IfNode
          branch(node, want, node.statements, node.subsequent.is_a?(Prism::ElseNode) ? node.subsequent.statements : node.subsequent)
        when Prism::UnlessNode then branch(node, want, node.else_clause&.statements, node.statements)
        when Prism::WhileNode then loop_while(node)
        when Prism::ReturnNode
          value, type = node.arguments ? expr(node.arguments.arguments.first, @d.ret) : [nil, "Void"]
          refuse(node, "a return of #{type} from a def whose sig says #{@d.ret}") unless fits?(@d.ret, type)
          @f.ins(type == "Void" ? "return" : "return #{value}")
          [nil, "Void"]
        else
          refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not in the kernel dialect")
        end
      end

      # A size or an offset: an integer, a constant, or an operator over
      # those, folded at compile time.
      def immediate(node)
        @unit.fold(node)
      end

      # An integer literal, or a constant, takes the type wanted here.
      def literal(node, n, want)
        type = want || "Word"
        refuse(node, "an integer where a #{type} is wanted") if clif(type).nil? || clif(type) == "f64"
        [@f.iconst(clif(type), n), type]
      end

      def call(node, want)
        args = node.arguments&.arguments || []
        if node.receiver.nil?
          target(node, node.name.to_s, args)
        elsif @unit.machine?(node.receiver)
          intrinsic(node, args, want)
        elsif node.name == :! && args.empty?
          value, type = condition_value(node.receiver)
          [@f.icmp("eq", value, @f.iconst(clif(type), 0)), "Bool"]
        elsif node.name == :-@ && args.empty?
          value, type = expr(node.receiver, want)
          refuse(node, "a negation of a #{type}") unless clif(type) && clif(type) != "f64"
          [@f.isub(@f.iconst(clif(type), 0), value), type]
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
          refuse(args[1], "#{layout.name}.#{fname} is a #{type}, not a #{vt}") unless clif(vt) == clif(type)
          @f.store(value, ptr, off)
          [nil, "Void"]
        else
          [@f.fetch(clif(type), ptr, off), type]
        end
      end

      # `a && b` and `a || b`, the right side lowered only when the left
      # decides nothing; the result is a Bool.
      def logical(node, op)
        left, lt = condition_value(node.left)
        bit = @f.icmp("ne", left, @f.iconst(clif(lt), 0))
        rest = @f.label
        skip = @f.label
        merge, params = @f.block(["i8"])
        op == :and ? @f.brif(bit, rest, skip) : @f.brif(bit, skip, rest)
        @f.switch(skip)
        @f.jump(merge, [bit])
        @f.switch(rest)
        right, rt = condition_value(node.right)
        @f.jump(merge, [@f.icmp("ne", right, @f.iconst(clif(rt), 0))])
        @f.switch(merge)
        [params.first, "Bool"]
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
        refuse(node, "#{op} on #{lt} and #{rt}") unless clif(lt) && (lt == rt || (PLAIN.include?(lt) && PLAIN.include?(rt)))
        ptr = lt == "Ptr" || rt == "Ptr"
        result = if ptr && op == :- && lt == rt then "Word"
                 elsif ptr then "Ptr"
                 else lt
                 end
        case op
        when :+, :-, :*, :&, :|, :^, :<<
          [@f.val("#{OPERATORS[op]} #{lhs}, #{rhs}"), result]
        when :/, :%, :>>
          mnemonic = { :/ => "div", :% => "rem", :>> => "shr" }[op]
          [@f.val("#{ptr ? "u" : "s"}#{mnemonic} #{lhs}, #{rhs}"), result]
        when :==, :!=
          [@f.val("icmp #{OPERATORS[op]} #{lhs}, #{rhs}"), "Bool"]
        when :<, :<=, :>, :>=
          cond = (ptr ? "u" : "s") + OPERATORS[op]
          [@f.val("icmp #{cond} #{lhs}, #{rhs}"), "Bool"]
        else
          refuse(node, "#{op} is not in the kernel dialect")
        end
      end

      PLAIN = %w[Word Ptr].freeze

      def fits?(want, got)
        want == got || (PLAIN.include?(want) && PLAIN.include?(got))
      end

      # A call to an import or to a def of this file.
      def target(node, name, args)
        callee = @unit.import_for(name) || @unit.def_for(name) or refuse(node, "#{name} is not an import or a machine def here")
        refuse(node, "#{name} takes #{callee.params.size} arguments, not #{args.size}") if args.size != callee.params.size
        types = callee.is_a?(Def) ? callee.params.map(&:last) : callee.params
        values = args.zip(types).map do |arg, type|
          value, got = expr(arg, type)
          refuse(arg, "#{name} wants a #{type} here, not a #{got}") unless fits?(type, got)
          value
        end
        fn = @f.callee(name, types.map { |t| clif(t) }, clif(callee.ret), colocated: !callee.is_a?(Import))
        if callee.ret == "Void"
          @f.ins "call #{fn}(#{values.join(", ")})"
          [nil, "Void"]
        else
          [@f.val("call #{fn}(#{values.join(", ")})"), callee.ret]
        end
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
            value
          end
          sig = @f.sig(s.params.map { |t| clif(t) }, clif(s.ret))
          return [@f.call_indirect(sig, ptr, values), "Void"] if s.ret == "Void"

          [@f.call_indirect_val(sig, ptr, values), s.ret]
        when :bytes
          s = args.first
          refuse(node, "Machine.bytes takes a string literal") unless s.is_a?(Prism::StringNode)
          [@f.val("symbol_value.i64 #{@f.symbol(@unit.bytes(s.unescaped))}"), "Ptr"]
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
          refuse(node, "#{node.name} stores a #{type}, not a #{vt}") unless clif(vt) == clif(type)
          @f.store(value, ptr, immediate(args[1]))
          [nil, "Void"]
        when :slot
          refuse(node, "Machine.slot takes a size") unless args.size == 1
          [@f.stack_addr(@f.slot(immediate(args.first))), "Ptr"]
        when :static
          name, size = args
          refuse(node, "Machine.static takes a symbol and a size") unless name.is_a?(Prism::SymbolNode) && size
          [@f.val("symbol_value.i64 #{@f.symbol(@unit.static(node, name.unescaped, immediate(size)))}"), "Ptr"]
        when :i32, :i8, :word, :sword, :ptr, :value
          value, type = expr(args.first)
          convert(node, node.name, value, type)
        when :addr
          name = args.first
          refuse(node, "Machine.addr takes the symbol of a machine def") unless name.is_a?(Prism::SymbolNode)
          d = @unit.def_for(name.unescaped) or refuse(node, "#{name.unescaped} is not a machine def here")
          fn = @f.callee(d.name, d.params.map { |_, t| clif(t) }, clif(d.ret), colocated: true)
          [@f.val("func_addr.i64 #{fn}"), "Ptr"]
        else
          refuse(node, "Machine.#{node.name} is not an intrinsic")
        end
      end

      # A width or a reading change: `Machine.i32(x)` narrows, `word`
      # zero-extends, `sword` sign-extends, `ptr`/`value`/`word` between
      # 64-bit types is only a reading.
      def convert(node, to, value, type)
        target = { i32: "I32", i8: "I8", word: "Word", sword: "Word", ptr: "Ptr", value: "Value" }[to]
        from, into = clif(type), clif(target)
        refuse(node, "Machine.#{to} of a #{type}") if from.nil? || from == "f64"
        return [value, target] if from == into
        return [@f.val("ireduce.#{into} #{value}"), target] if from == "i64" || (from == "i32" && into == "i8")

        [@f.val("#{to == :sword ? "sextend" : "uextend"}.#{into} #{value}"), target]
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
        @f.ins "brif #{cond}, #{then_b}, #{else_b}"
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
        merge, params = joined == "Void" ? @f.block : @f.block([clif(joined)])
        @f.finish(then_end, "jump #{merge}#{joined == "Void" ? "" : "(#{tv})"}") if then_open
        @f.finish(else_end, "jump #{merge}#{joined == "Void" ? "" : "(#{ev})"}") if else_open
        @f.switch(merge, open: true)
        [joined == "Void" ? nil : params.first, joined]
      end

      def loop_while(node)
        head = @f.label
        body = @f.label
        done = @f.label
        @f.ins "jump #{head}"
        @f.switch(head)
        cond = condition(node)
        @f.ins "brif #{cond}, #{body}, #{done}"
        @f.switch(body)
        statements(node.statements) if node.statements
        @f.ins "jump #{head}" unless @f.terminated?
        @f.switch(done)
        [nil, "Void"]
      end
    end
  end
end
