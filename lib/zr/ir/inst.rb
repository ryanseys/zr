# frozen_string_literal: true

module Zr
  module IR
    # The first byte of a value name. Each entity name is a sigil and a
    # number, and only a value name starts with `v`.
    VALUE_SIGIL = "v".ord

    # Whether `name` is a value name. Only values have names that start
    # with `v`: a block is `block0`, a global `gv0`, a slot `ss0`, a callee
    # `fn0` and a signature `sig0`.
    #
    # This compares one byte and does not use `start_with?`, because that
    # method takes `*prefixes` and makes an Array at each call. The
    # compiler calls this method more than any other: 19 million times in
    # one cold runtime build.
    #: (untyped name) -> bool
    def self.value?(name) = name.is_a?(String) && name.getbyte(0) == VALUE_SIGIL

    # One instruction, with only the opcodes that zr emits: an opcode, its
    # type (`iadd.i64`, or none), its operands, its results, and the fields
    # of the control and memory forms.
    #
    # Operands are value names (`"v3"`), block names (`"block2"`), entity
    # names (`"fn0"`, `"gv1"`, `"ss2"`) or an Integer immediate.
    #
    # The IR defines the result of each opcode. Each backend and the
    # interpreter must give the same result (test/native/fixtures.rb
    # `divide` tests this):
    #
    # - i8 and i32 arithmetic is 32 bits wide, and i64 is 64 bits wide.
    # - `udiv` and `sdiv` by zero give 0; `urem` and `srem` by zero give
    #   the dividend.
    # - The most negative number `sdiv` -1 wraps to itself, and `srem` -1
    #   gives 0.
    # - A shift uses its amount modulo the width.
    # - `ctz` and `clz` of zero give the width; `popcnt` counts the set
    #   bits; `bswap` reverses the bytes. All four are as wide as their
    #   operand, which is i32 or i64.
    # - A function takes, and a call passes, at most `REGISTER_ARGS` values.
    #   A call to a wasm import passes all the arguments of the import,
    #   because no native backend makes such a call.
    class Inst
      # Opcodes that end a block. A `switch` is a jump table: its first
      # operand is an integer value, the others are its keys (Integers,
      # masked to the value's type, in rising order), and its targets are
      # the default and then one target for each key. Like a `brif`, it
      # passes no block arguments.
      TERMINATORS = %i[jump brif switch return].freeze
      # Opcodes with two results.
      PAIRS = %i[sadd_overflow ssub_overflow smul_overflow].freeze
      # The two-operand integer opcodes with one result.
      BINOPS = %i[iadd isub imul udiv sdiv urem srem band bor bxor ishl ushr sshr].freeze
      # The shifts. Their amount can be any integer width.
      SHIFTS = %i[ishl ushr sshr].freeze
      # The opcodes whose operands can change places.
      COMMUTATIVE = %i[iadd imul band bor bxor].freeze
      # The one-operand integer opcodes: the bit operations.
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
      # The gate word. The kernel keeps it in its own register (`x28`; a
      # global on wasm). `gates` reads it. `gates_set` writes it after a
      # store of the word. `gates_enter` loads it where foreign code enters
      # compiled code; at return, the register gets back the value of the
      # foreign code.
      GATES = %i[gates gates_set gates_enter].freeze

      # `region`: for a load or a store, the `IR::Effects` region of the
      # word, or nil when the lowering does not know it.
      attr_accessor :op #: Symbol
      attr_accessor :type #: String?
      attr_accessor :args #: Array[untyped]
      attr_accessor :results #: Array[String]
      attr_accessor :cond #: String?
      attr_accessor :offset #: Integer
      attr_accessor :targets #: Array[untyped]?
      attr_accessor :callee #: String?
      attr_accessor :flags #: untyped
      attr_accessor :region #: untyped

      # @rbs op: Symbol
      # @rbs type: String?
      # @rbs args: Array[untyped]
      # @rbs results: Array[String]
      # @rbs cond: String?
      # @rbs offset: Integer
      # @rbs targets: Array[untyped]?
      # @rbs callee: String?
      # @rbs flags: untyped
      # @rbs region: untyped
      # @rbs return: void
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

      #: () -> bool
      def terminator?
        TERMINATORS.include?(@op)
      end
    end
  end
end
