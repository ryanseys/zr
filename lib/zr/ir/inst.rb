# frozen_string_literal: true

module Zr
  module IR
    # The byte a value's name starts with. Every entity is named by a
    # sigil and a number, and only a value's is `v`.
    VALUE_SIGIL = "v".ord

    # Whether `name` names a value. A value is the only entity the
    # builder names with a leading `v`: a block is `block0`, a global
    # `gv0`, a slot `ss0`, a callee `fn0` and a signature `sig0`.
    #
    # The byte, and not `start_with?`, which takes a `*prefixes`
    # parameter and so makes an Array of every call. This is the
    # compiler's most asked question -- 19 million times in one cold
    # runtime build, more than any other method reaches in the whole of
    # one -- and it is asked of one byte.
    def self.value?(name) = name.is_a?(String) && name.getbyte(0) == VALUE_SIGIL

    # One instruction, restricted to the opcodes zr emits: an
    # opcode, the type written on it (`iadd.i64`, or none), its operands,
    # its results, and for the control and memory forms their own fields.
    #
    # Operands are value names (`"v3"`), block names (`"block2"`), entity
    # names (`"fn0"`, `"gv1"`, `"ss2"`) or an Integer immediate.
    #
    # What an opcode answers is the IR's to say, and every backend and the
    # interpreter owe the same answer (test/native/fixtures.rb `divide`
    # holds them to it):
    #
    # - i8 and i32 arithmetic is done 32 bits wide, and i64 64 bits.
    # - `udiv` and `sdiv` by zero answer 0; `urem` and `srem` by zero
    #   answer the dividend.
    # - The most negative number `sdiv` -1 wraps to itself, and `srem` -1
    #   answers 0.
    # - A shift takes its amount modulo the width.
    # - `ctz` and `clz` of zero answer the width; `popcnt` counts the set
    #   bits; `bswap` reverses the bytes of the word, all four as wide
    #   as their operand, which is i32 or i64.
    # - A function takes, and a call passes, at most `REGISTER_ARGS` values;
    #   a call to a wasm import passes what the import takes, since no
    #   native backend makes one.
    class Inst
      # Opcodes that end a block.
      TERMINATORS = %i[jump brif return].freeze
      # Opcodes with two results.
      PAIRS = %i[sadd_overflow ssub_overflow smul_overflow].freeze
      # The two-operand integer opcodes with one result.
      BINOPS = %i[iadd isub imul udiv sdiv urem srem band bor bxor ishl ushr sshr].freeze
      # The shifts, whose amount may be any integer width.
      SHIFTS = %i[ishl ushr sshr].freeze
      # The ones whose operands may trade places.
      COMMUTATIVE = %i[iadd imul band bor bxor].freeze
      # The one-operand integer opcodes: the bit tricks.
      BITOPS = %i[ctz clz popcnt bswap].freeze
      # The comparison conditions.
      CONDS = %w[eq ne slt sle sgt sge ult ule ugt uge].freeze
      # The two-operand and one-operand f64 opcodes.
      FBINOPS = %i[fadd fsub fmul fdiv].freeze
      FUNOPS = %i[fneg fabs sqrt floor ceil trunc nearest].freeze
      # Float comparisons: false when either side is NaN, except `ne`.
      FCONDS = %w[eq ne lt le gt ge].freeze
      # The conversions between i64 and f64: by value, and by bits.
      CONVERSIONS = %i[fcvt_from_sint fcvt_to_sint_sat bitcast].freeze
      # The gate word, which the kernel keeps in a register of its own
      # (`x28`; a global on wasm): `gates` reads it, `gates_set` writes
      # it after a store of the word, and `gates_enter` loads it where
      # foreign code enters compiled code, the register then given back
      # as that code left it.
      GATES = %i[gates gates_set gates_enter].freeze

      # `region`: for a load or a store, the `IR::Effects` region of the
      # word, or nil when the lowering could not place it.
      attr_accessor :op, :type, :args, :results, :cond, :offset, :targets, :callee, :flags, :region

      # rubocop:disable Metrics/ParameterLists
      def initialize(op, type: nil, args: [], results: [], cond: nil, offset: 0, targets: nil, callee: nil, flags: nil,
                     region: nil)
        @op = op
        @type = type
        @args = args
        @results = results
        @cond = cond
        @offset = offset
        @targets = targets
        @callee = callee
        @flags = flags
        @region = region
      end
      # rubocop:enable Metrics/ParameterLists

      def terminator?
        TERMINATORS.include?(@op)
      end
    end
  end
end
