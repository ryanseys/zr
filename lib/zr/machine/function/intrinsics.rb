# frozen_string_literal: true

# `Machine::Function`'s intrinsics: the lowering of each `Machine.*` call,
# one method for each family.

module Zr
  module Machine
    class Function
      # The bytes of the slot of a C va_list (`Machine.va_list`), by the
      # kind of its ABI: darwin arm64's is the address of the next
      # argument; AAPCS64's is a 32-byte struct and its save areas for the
      # eight x registers and the eight v registers (16 bytes each).
      VA_LIST_KINDS = { 0 => 8, 1 => 32 + 64 + 128 }.freeze

      # The IR width and the Machine type that each load and store gives or
      # takes, and the Machine type of each conversion.
      LOAD_WIDTHS = { load64: "i64", load32: "i32", load8: "i8" }.freeze #: Hash[Symbol, String]
      LOAD_TYPES = { load64: "Word", load32: "I32", load8: "I8" }.freeze #: Hash[Symbol, String]
      STORE_TYPES = { store64: "Word", store32: "I32", store8: "I8" }.freeze #: Hash[Symbol, String]
      CONVERT_TARGETS = { i32: "I32", i8: "I8", word: "Word", sword: "Word", ptr: "Ptr", value: "Value" }.freeze #: Hash[Symbol, String]

      # The number of operands of each intrinsic whose arm does not count
      # them itself.
      OPERANDS = {
        load64: 2, load32: 2, load8: 2, store64: 3, store32: 3, store8: 3, gates_set: 1,
        i32: 1, i8: 1, word: 1, sword: 1, ptr: 1, value: 1, u8: 1, u32: 1,
        f64: 1, bits: 1, to_f64: 1, to_int: 1, ctz: 1, clz: 1, popcnt: 1, bswap: 1,
        sqrt: 1, floor: 1, ceil: 1, trunc: 1, nearest: 1, fabs: 1
      }.freeze #: Hash[Symbol, Integer]

      COUNTS = %w[no one two three].freeze #: Array[String]

      private

      # `Machine.name(args)`, by its family. Each arm checks the class of
      # the arguments that it reads.
      #: (Prism::CallNode node, Array[untyped] args, String? want) -> [untyped, String]
      def intrinsic(node, args, want)
        if (n = OPERANDS[node.name]) && args.size != n
          refuse(node, "Machine.#{node.name} takes #{COUNTS.fetch(n)} operand#{"s" if n > 1}")
        end
        case node.name
        when :id, :bytesize, :extern, :bytes, :addr then named(node, args, want)
        when :load64, :load32, :load8, :store64, :store32, :store8, :slot, :static, :global, :va_list then memory(node, args)
        when :gates, :gates_set, :gates_enter then machine_state(node, args)
        when :i32, :i8, :word, :sword, :ptr, :value, :u8, :u32, :f64, :bits, :to_f64, :to_int then conversion(node, args)
        when :add_wrap, :sub_wrap, :mul_wrap, :shl_wrap, :uadd_wrap, :usub_wrap, :umul_wrap, :ushl_wrap, :sdiv, :srem,
             :ctz, :clz, :popcnt, :bswap, :sqrt, :floor, :ceil, :trunc, :nearest, :fabs
          arithmetic(node, args, want)
        else refuse(node, "Machine.#{node.name} is not an intrinsic")
        end
      end

      # The intrinsics that name a thing at build time: a symbol's id, a
      # literal's size or bytes, another unit's data, a machine def.
      #: (Prism::CallNode node, Array[untyped] args, String? want) -> [untyped, String]
      def named(node, args, want)
        name = args.first
        case node.name
        when :id
          refuse(node, "Machine.id takes a symbol") unless name.is_a?(Prism::SymbolNode) && args.size == 1
          literal(node, @unit.symbols.id(name.unescaped), want)
        when :bytesize
          refuse(node, "Machine.bytesize takes a string literal") unless name.is_a?(Prism::StringNode)
          literal(node, name.unescaped.bytesize, want)
        when :extern
          refuse(node, "Machine.extern takes the symbol of a data object another unit defines") unless name.is_a?(Prism::SymbolNode)
          [@f.symbol_value(@f.symbol(name.unescaped, colocated: false)), "Ptr"]
        when :bytes
          refuse(node, "Machine.bytes takes a string literal") unless name.is_a?(Prism::StringNode)
          [@f.symbol_value(@f.symbol(@unit.bytes(name.unescaped))), "Ptr"]
        else # :addr
          refuse(node, "Machine.addr takes the symbol of a machine def") unless name.is_a?(Prism::SymbolNode)
          d = @unit.def_for(name.unescaped) or refuse(node, "#{name.unescaped} is not a machine def here")
          fn = @f.callee(d.name, d.params.map { |_, t| ir_type(t) }, ir_type(d.ret), colocated: true)
          [@f.func_addr(fn), "Ptr"]
        end
      end

      # The intrinsics that read, write or reserve memory: loads, stores,
      # stack slots, statics, globals and a C va_list.
      #: (Prism::CallNode node, Array[untyped] args) -> [untyped, String]
      def memory(node, args)
        case node.name
        when :load64, :load32, :load8
          width = LOAD_WIDTHS[node.name]
          ptr, pt = expr(args[0], "Ptr")
          refuse(node, "#{node.name} takes a Ptr and an offset") unless fits?("Ptr", pt)
          type = LOAD_TYPES[node.name]
          [@f.fetch(width, ptr, immediate(args[1])), type]
        when :store64, :store32, :store8
          ptr, pt = expr(args[0], "Ptr")
          refuse(node, "#{node.name} takes a Ptr, an offset and a value") unless fits?("Ptr", pt)
          type = STORE_TYPES[node.name]
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
        when :global
          name, size = args
          unless name.is_a?(Prism::SymbolNode) && args.size <= 2
            refuse(node, "Machine.global takes the symbol of the area and its size")
          end
          [@f.symbol_value(@f.symbol(@unit.global(node, name.unescaped, size ? immediate(size) : 8))), "Ptr"]
        else # :va_list
          refuse(node, "Machine.va_list takes the kind of its C ABI") unless args.size == 1
          kind = immediate(args.first)
          refuse(node, "Machine.va_list: no C ABI of kind #{kind}") unless VA_LIST_KINDS.key?(kind)
          [@f.va_list(@f.slot(VA_LIST_KINDS.fetch(kind)), kind), "Ptr"]
        end
      end

      # The intrinsics of the gate word (`gates_addr`).
      #: (Prism::CallNode node, Array[untyped] args) -> [untyped, String]
      def machine_state(node, args)
        case node.name
        when :gates
          refuse(node, "Machine.gates takes nothing") unless args.empty?
          [@f.gates, "Word"]
        when :gates_set
          value, type = expr(args.first, "Word")
          refuse(node, "Machine.gates_set takes a Word") unless ir_type(type) == "i64"
          @f.store(value, gates_addr(node), region: :gates)
          @f.gates_set(value)
          [nil, "Void"]
        else # :gates_enter
          refuse(node, "Machine.gates_enter takes nothing") unless args.empty?
          @f.gates_enter(@f.fetch("i64", gates_addr(node), region: :gates))
          [nil, "Void"]
        end
      end

      # The intrinsics that change the width or the type of a value
      # (`convert`, `float_convert`).
      #: (Prism::CallNode node, Array[untyped] args) -> [untyped, String]
      def conversion(node, args)
        case node.name
        when :i32, :i8, :word, :sword, :ptr, :value
          # `Machine.word(0x8080808080808080)`: the bits of a literal
          # that does not fit a signed Word.
          return literal(args.first, args.first.value, "Word") if node.name == :word && args.first.is_a?(Prism::IntegerNode)

          value, type = expr(args.first)
          # Ruby keeps the sign of an I8 or I32, so a widening says which
          # bits it means.
          if %i[word ptr value].include?(node.name) && %w[I8 I32].include?(type)
            refuse(node, "Machine.#{node.name} of an #{type} is Machine.#{type == "I8" ? "u8" : "u32"} (zero-extend) or Machine.sword (sign-extend)")
          end
          convert(node, node.name, value, type)
        when :u8, :u32
          value, type = expr(args.first)
          narrow = node.name == :u8 ? "i8" : "i32"
          refuse(node, "Machine.#{node.name} of a #{type}") unless ir_type(type) == narrow
          convert(node, :word, value, type)
        else # :f64, :bits, :to_f64, :to_int
          value, type = expr(args.first)
          float_convert(node, node.name, value, type) #: [String, String]
        end
      end

      # The intrinsics that compute: the wrapping operators, signed
      # division, the bit counts and the float functions.
      #: (Prism::CallNode node, Array[untyped] args, String? want) -> [untyped, String]
      def arithmetic(node, args, want)
        case node.name
        when :add_wrap, :sub_wrap, :mul_wrap, :shl_wrap, :uadd_wrap, :usub_wrap, :umul_wrap, :ushl_wrap
          refuse(node, "Machine.#{node.name} takes two operands") unless args.size == 2
          lhs, lt = expr(args[0], want)
          rhs, rt = expr(args[1], lt)
          refuse(node, "Machine.#{node.name} of an F64") if lt == "F64" || rt == "F64"
          unsigned = node.name.start_with?("u")
          unless lt == (unsigned ? "Ptr" : "Word")
            refuse(node, "Machine.#{node.name} of a #{lt}; #{unsigned ? "it wraps a Ptr" : "a Ptr wraps by Machine.u#{node.name}"}")
          end
          binary(node, WRAPS.fetch(node.name), lhs, lt, rhs, rt, named: true)
        when :sdiv, :srem
          refuse(node, "Machine.#{node.name} takes two operands") unless args.size == 2
          lhs, lt = expr(args[0], want)
          rhs, rt = expr(args[1], lt)
          refuse(node, "Machine.#{node.name} of a #{lt} and a #{rt}") unless %w[I8 I32 Word].include?(lt) && lt == rt
          binary(node, node.name == :sdiv ? :/ : :%, lhs, lt, rhs, rt, named: true)
        when :ctz, :clz, :popcnt, :bswap
          value, type = expr(args.first)
          # CRuby keeps no width, so these count the 64 bits of a word.
          if ir_type(type) == "i32"
            refuse(node, "Machine.#{node.name} of an I32 counts 64 bits on CRuby; widen it first (Machine.u32)")
          end
          refuse(node, "Machine.#{node.name} of a #{type}") unless ir_type(type) == "i64"
          op = node.name #: IR::op
          [@f.bitop(op, value), type]
        else # :sqrt, :floor, :ceil, :trunc, :nearest, :fabs
          value, type = expr(args.first)
          refuse(node, "Machine.#{node.name} of a #{type}") unless type == "F64"
          op = node.name #: IR::op
          [@f.funop(op, value), "F64"]
        end
      end

      # The static of the gate word. `Machine.gates` reads the word from
      # its register. `Machine.gates_set(word)` stores the word and sets
      # the register. `Machine.gates_enter` is first in a def that foreign
      # code calls; it loads the register from the static, and the def
      # restores the register before it returns.
      #: (Prism::node node) -> String
      def gates_addr(node)
        @f.symbol_value(@f.symbol(@unit.static(node, "gates", 8)))
      end

      # A change of width or of type: `Machine.i32(x)` narrows, `u8` and
      # `u32` zero-extend, `sword` sign-extends. `ptr`, `value` and `word`
      # between 64-bit types change only the type, not the bits.
      #: (Prism::node node, Symbol to, String value, String type) -> [String, String]
      def convert(node, to, value, type)
        target = CONVERT_TARGETS[to]
        from, into = ir_type(type), ir_type(target)
        refuse(node, "Machine.#{to} of a #{type}") if from.nil? || from == "f64"
        return [value, target] if from == into
        return [@f.ireduce(into, value), target] if from == "i64" || (from == "i32" && into == "i8")

        [to == :sword ? @f.sextend(into, value) : @f.uextend(into, value), target]
      end

      # `Machine.f64(word)` and `Machine.bits(f)` read the same 64 bits
      # as the other type. `to_f64` and `to_int` convert the value;
      # `to_int` saturates.
      #: (Prism::node node, Symbol to, String value, String type) -> [String, String]?
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
    end
  end
end
