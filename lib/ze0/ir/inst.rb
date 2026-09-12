# frozen_string_literal: true

module Ze0
  module IR
    # One instruction, restricted to the opcodes ze0 emits: an
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
      # The two-operand integer opcodes with one result.
      BINOPS = %i[iadd isub imul udiv sdiv urem srem band bor bxor ishl ushr sshr].freeze
      # The comparison conditions.
      CONDS = %w[eq ne slt sle sgt sge ult ule ugt uge].freeze
      # The two-operand and one-operand f64 opcodes.
      FBINOPS = %i[fadd fsub fmul fdiv].freeze
      FUNOPS = %i[fneg fabs sqrt floor ceil trunc nearest].freeze
      # Float comparisons: false when either side is NaN, except `ne`.
      FCONDS = %w[eq ne lt le gt ge].freeze
      # The conversions between i64 and f64: by value, and by bits.
      CONVERSIONS = %i[fcvt_from_sint fcvt_to_sint_sat bitcast].freeze

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
    end
  end
end
