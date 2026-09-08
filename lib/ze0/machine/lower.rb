# frozen_string_literal: true

require "prism"
require_relative "../ir"
require_relative "../obj/model"

module Ze0
  # The kernel dialect: Ruby syntax, machine semantics. A file of
  # `Machine.import` declarations and `sig`-typed `machine def`s lowers
  # straight to IR, one function per def. Types are `I8 I32 Word Ptr Value
  # F64 Bool Void`; every local takes its type from its first assignment
  # and lives in a frame slot; a call names an import or a def of the same
  # file. A form outside the dialect is refused by name at its line.
  module Machine
    class Refused < StandardError
      attr_reader :line

      def initialize(node, message)
        @line = node.location.start_line
        super("line #{@line}: #{message}")
      end
    end

    TYPES = {
      "I8" => "i8", "Bool" => "i8", "I32" => "i32", "Word" => "i64", "Ptr" => "i64",
      "Value" => "i64", "F64" => "f64", "Void" => nil
    }.freeze
    # Comparisons that read their operands as unsigned: pointers.
    UNSIGNED = %w[Ptr].freeze

    Import = Struct.new(:name, :params, :ret)
    Def = Struct.new(:name, :params, :ret, :node)

    # `source` to `[functions, data]`: IR functions and the data objects
    # they name.
    def self.compile(source, file)
      Lower.new(source, file).run
    end

    class Lower
      attr_reader :functions, :data

      def initialize(source, file)
        @source = source
        @file = file
        @imports = {}
        @defs = {}
        @functions = []
        @data = []
        @next_bytes = 0
      end

      def run
        result = Prism.parse(@source, filepath: @file)
        unless result.errors.empty?
          e = result.errors.first
          raise SyntaxError, "#{@file}:#{e.location.start_line}: #{e.message}"
        end

        declare(result.value.statements.body)
        @defs.each_value { |d| @functions << Function.new(self, d).lower }
        [@functions, @data]
      end

      # The file's declarations: imports, and each `sig` with its def.
      def declare(statements)
        pending_sig = nil
        statements.each do |node|
          refuse(node, "a statement that is not an import, a sig or a machine def") unless node.is_a?(Prism::CallNode)
          case node.name
          when :import
            refuse(node, "an import is `Machine.import \"name\", [types] => type`") unless machine?(node.receiver)
            name, sig = node.arguments.arguments
            params, ret = signature(sig)
            @imports[name.unescaped] = Import.new(name.unescaped, params, ret)
          when :sig
            refuse(node, "a sig is `sig [types] => type`") unless node.receiver.nil?
            pending_sig = signature(node.arguments.arguments.first)
          when :machine
            d = node.arguments&.arguments&.first
            refuse(node, "`machine` takes a def") unless d.is_a?(Prism::DefNode)
            refuse(d, "a machine def has no sig ahead of it") if pending_sig.nil?
            params, ret = pending_sig
            pending_sig = nil
            names = (d.parameters&.requireds || []).map(&:name)
            refuse(d, "the sig has #{params.size} types for #{names.size} parameters") if names.size != params.size
            refuse(d, "a machine def takes required parameters only") if d.parameters && d.parameters.child_nodes.compact.size != names.size
            @defs[d.name.to_s] = Def.new(d.name.to_s, names.zip(params), ret, d)
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

      def machine?(node)
        node.is_a?(Prism::ConstantReadNode) && node.name == :Machine
      end

      def import_for(name)
        @imports[name]
      end

      def def_for(name)
        @defs[name]
      end

      # A read-only byte string, as a data object this unit carries.
      def bytes(string)
        name = "zr_bytes_#{@next_bytes}"
        @next_bytes += 1
        @data << Obj::Data.new(name, :text_const, string, align: 1)
        name
      end

      def refuse(node, message)
        raise Refused.new(node, message)
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
          refuse(@d.node, "the body ends in #{type}, and the sig says #{@d.ret}") unless type == @d.ret
          @f.ins "return #{value}"
        end
        @f
      end

      private

      def refuse(node, message)
        raise Refused.new(node, message)
      end

      def declare_local(node, name, type)
        refuse(node, "#{name} is already a #{@locals[name][:type]}") if @locals.key?(name) && @locals[name][:type] != type
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
        when Prism::IntegerNode
          type = want || "Word"
          refuse(node, "an integer where a #{type} is wanted") if clif(type).nil? || clif(type) == "f64"
          [@f.iconst(clif(type), node.value), type]
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
        when Prism::IfNode then branch(node, want)
        when Prism::WhileNode then loop_while(node)
        when Prism::ReturnNode
          value, type = node.arguments ? expr(node.arguments.arguments.first, @d.ret) : [nil, "Void"]
          refuse(node, "a return of #{type} from a def whose sig says #{@d.ret}") unless type == @d.ret
          @f.ins(type == "Void" ? "return" : "return #{value}")
          [nil, "Void"]
        else
          refuse(node, "#{node.class.name.split("::").last.delete_suffix("Node")} is not in the kernel dialect")
        end
      end

      def call(node, want)
        args = node.arguments&.arguments || []
        if node.receiver.nil?
          return binary_call(node, want) if node.name.to_s.match?(/\A[+\-&|<>=!]/)

          target(node, node.name.to_s, args)
        elsif @unit.machine?(node.receiver)
          intrinsic(node, args)
        elsif node.arguments&.arguments&.size == 1 && OPERATORS.key?(node.name)
          lhs, lt = expr(node.receiver, want)
          rhs, rt = expr(args.first, lt)
          binary(node, node.name, lhs, lt, rhs, rt)
        else
          refuse(node, "a call with a receiver that is not Machine")
        end
      end

      def binary_call(node, want)
        refuse(node, "an operator with no receiver")
      end

      OPERATORS = {
        :+ => "iadd", :- => "isub", :& => "band", :| => "bor",
        :< => "lt", :<= => "le", :> => "gt", :>= => "ge", :== => "eq", :!= => "ne"
      }.freeze

      def binary(node, op, lhs, lt, rhs, rt)
        refuse(node, "#{op} on #{lt} and #{rt}") unless lt == rt && clif(lt)
        case op
        when :+, :-, :&, :|
          [@f.val("#{OPERATORS[op]} #{lhs}, #{rhs}"), lt]
        when :==, :!=
          [@f.val("icmp #{OPERATORS[op]} #{lhs}, #{rhs}"), "Bool"]
        when :<, :<=, :>, :>=
          cond = (UNSIGNED.include?(lt) ? "u" : "s") + OPERATORS[op]
          [@f.val("icmp #{cond} #{lhs}, #{rhs}"), "Bool"]
        else
          refuse(node, "#{op} is not in the kernel dialect")
        end
      end

      # A call to an import or to a def of this file.
      def target(node, name, args)
        callee = @unit.import_for(name) || @unit.def_for(name) or refuse(node, "#{name} is not an import or a machine def here")
        refuse(node, "#{name} takes #{callee.params.size} arguments, not #{args.size}") if args.size != callee.params.size
        types = callee.is_a?(Import) ? callee.params : callee.params.map(&:last)
        values = args.zip(types).map do |arg, type|
          value, got = expr(arg, type)
          refuse(arg, "#{name} wants a #{type} here, not a #{got}") unless got == type
          value
        end
        fn = @f.callee(name, types.map { |t| clif(t) }, clif(callee.ret), colocated: callee.is_a?(Def))
        if callee.ret == "Void"
          @f.ins "call #{fn}(#{values.join(", ")})"
          [nil, "Void"]
        else
          [@f.val("call #{fn}(#{values.join(", ")})"), callee.ret]
        end
      end

      def intrinsic(node, args)
        case node.name
        when :bytes
          s = args.first
          refuse(node, "Machine.bytes takes a string literal") unless s.is_a?(Prism::StringNode)
          [@f.val("symbol_value.i64 #{@f.symbol(@unit.bytes(s.unescaped))}"), "Ptr"]
        when :load64, :load32, :load8
          width = { load64: "i64", load32: "i32", load8: "i8" }[node.name]
          ptr, pt = expr(args[0], "Ptr")
          refuse(node, "#{node.name} takes a Ptr and an offset") unless pt == "Ptr" && args[1].is_a?(Prism::IntegerNode)
          type = { load64: "Word", load32: "I32", load8: "I8" }[node.name]
          [@f.val("load.#{width} notrap aligned #{ptr}#{args[1].value.zero? ? "" : "+#{args[1].value}"}"), type]
        when :store64, :store32, :store8
          ptr, pt = expr(args[0], "Ptr")
          refuse(node, "#{node.name} takes a Ptr, an offset and a value") unless pt == "Ptr" && args[1].is_a?(Prism::IntegerNode)
          type = { store64: "Word", store32: "I32", store8: "I8" }[node.name]
          value, vt = expr(args[2], type)
          refuse(node, "#{node.name} stores a #{type}, not a #{vt}") unless clif(vt) == clif(type)
          @f.ins "store notrap aligned #{value}, #{ptr}#{args[1].value.zero? ? "" : "+#{args[1].value}"}"
          [nil, "Void"]
        when :slot
          refuse(node, "Machine.slot takes a size") unless args.first.is_a?(Prism::IntegerNode)
          [@f.stack_addr(@f.slot(args.first.value)), "Ptr"]
        else
          refuse(node, "Machine.#{node.name} is not an intrinsic")
        end
      end

      def condition(node)
        value, type = expr(node.predicate)
        refuse(node.predicate, "a condition that is a #{type}") unless %w[Bool I8 I32 Word Ptr Value].include?(type)
        value
      end

      # `if` as a value when both arms agree on a type, else Void.
      def branch(node, want)
        cond = condition(node)
        then_b = @f.label
        else_b = @f.label
        @f.ins "brif #{cond}, #{then_b}, #{else_b}"
        @f.switch(then_b)
        tv, tt = node.statements ? statements(node.statements, want) : [nil, "Void"]
        then_end = @f.terminated?
        merge = nil
        unless then_end
          merge, params = merge_block(tt)
          @f.ins "jump #{merge}#{params.empty? ? "" : "(#{tv})"}"
        end
        @f.switch(else_b)
        ev, et = if node.subsequent.is_a?(Prism::ElseNode)
                   node.subsequent.statements ? statements(node.subsequent.statements, want) : [nil, "Void"]
                 elsif node.subsequent
                   expr(node.subsequent, want)
                 else
                   [nil, "Void"]
                 end
        else_end = @f.terminated?
        return [nil, "Void"] if then_end && else_end

        joined = !then_end && !else_end && tt == et && tt != "Void" ? tt : "Void"
        merge ||= merge_block(joined).first
        merge, params = merge_block(joined) if joined == "Void" && merge.nil?
        unless else_end
          @f.ins "jump #{merge}#{joined == "Void" ? "" : "(#{ev})"}"
        end
        @f.switch(merge)
        [joined == "Void" ? nil : @merge_params[merge].first, joined]
      end

      def merge_block(type)
        @merge_params ||= {}
        name, params = type == "Void" ? @f.block : @f.block([clif(type)])
        @merge_params[name] = params
        [name, params]
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
