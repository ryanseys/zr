# frozen_string_literal: true

module Ze0
  module IR
    # One instruction, CLIF's model restricted to what ze0 emits: an
    # opcode, the type written on it (`iadd.i64`, or none), its operands,
    # its results, and for the control and memory forms their own fields.
    #
    # Operands are value names (`"v3"`), block names (`"block2"`), entity
    # names (`"fn0"`, `"gv1"`, `"ss2"`) or an Integer immediate.
    class Inst
      # Opcodes that end a block.
      TERMINATORS = %i[jump brif return].freeze
      # Opcodes with two results.
      PAIRS = %i[sadd_overflow ssub_overflow smul_overflow].freeze
      # The comparison conditions, as CLIF spells them.
      CONDS = %w[eq ne slt sle sgt sge ult ule ugt uge].freeze

      attr_accessor :op, :type, :args, :results, :cond, :offset, :targets, :callee, :flags

      # rubocop:disable Metrics/ParameterLists
      def initialize(op, type: nil, args: [], results: [], cond: nil, offset: 0, targets: nil, callee: nil, flags: nil)
        @op = op
        @type = type
        @args = args
        @results = results
        @cond = cond
        @offset = offset
        @targets = targets
        @callee = callee
        @flags = flags
      end
      # rubocop:enable Metrics/ParameterLists

      def terminator?
        TERMINATORS.include?(@op)
      end

      # The instruction the text spells. The text is what today's lowering
      # writes; this is the seam between text and structure, and it goes
      # away when the lowering builds instructions directly.
      def self.parse(text)
        results = []
        if (m = text.match(/\A(v\d+(?:, v\d+)?) = (.*)\z/))
          results = m[1].split(", ")
          text = m[2]
        end
        head, rest = text.split(" ", 2)
        op, type = head.split(".", 2)
        op = op.to_sym
        rest = rest.to_s
        case op
        when :call
          m = rest.match(/\A(fn\d+)\((.*)\)\z/) or raise ArgumentError, "a call is `call fnN(args)`: #{text}"
          new(op, results: results, callee: m[1], args: m[2].empty? ? [] : m[2].split(", "))
        when :jump
          new(op, targets: [target(rest)])
        when :brif
          cond, a, b = rest.split(", ", 3)
          new(op, args: [cond], targets: [target(a), target(b)])
        when :return
          new(op, args: rest.empty? ? [] : [rest])
        when :store
          flags, val, addr = rest.match(/\A((?:\w+ )*)(v\d+), (v\d+)(?:\+(\d+))?\z/).then { |mm| [mm[1].strip, mm[2], [mm[3], mm[4]]] }
          new(op, args: [val, addr[0]], offset: addr[1].to_i, flags: flags)
        when :load
          mm = rest.match(/\A((?:\w+ )*)(v\d+)(?:\+(\d+))?\z/) or raise ArgumentError, "a load is `load.T flags vN[+off]`: #{text}"
          new(op, type: type, results: results, args: [mm[2]], offset: mm[3].to_i, flags: mm[1].strip)
        when :iconst
          new(op, type: type, results: results, args: [Integer(rest)])
        when :stack_addr, :symbol_value, :func_addr, :ireduce, :uextend, :sextend
          new(op, type: type, results: results, args: [rest])
        when :icmp
          cond, a, b = rest.split(/[ ,]+/, 3)
          raise ArgumentError, "an icmp condition: #{text}" unless CONDS.include?(cond)

          new(op, type: type, results: results, cond: cond, args: [a, b])
        when :iadd, :isub, :imul, :udiv, :sdiv, :urem, :srem, :band, :bor, :bxor, :ishl, :ushr, :sshr, :select, *PAIRS
          new(op, type: type, results: results, args: rest.split(", "))
        else
          raise ArgumentError, "ze0 does not emit `#{op}`: #{text}"
        end
      end

      # `block3` or `block3(v1, v2)` as `[name, args]`.
      def self.target(text)
        m = text.match(/\A(block\d+)(?:\((.*)\))?\z/) or raise ArgumentError, "a block target: #{text}"
        [m[1], m[2] ? m[2].split(", ") : []]
      end
    end
  end
end
