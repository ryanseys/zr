# frozen_string_literal: true

require_relative "analysis"
require_relative "effects"
require_relative "inst"

module Zr
  module IR
    # The maximum number of function parameters and call arguments: eight.
    # Each native target has eight argument registers. Each lowering keeps
    # a signature to eight, so no backend needs stack arguments.
    REGISTER_ARGS = 8

    # The names of values and blocks are interned Strings. A Hash takes a
    # frozen key as it is, but copies and interns any other String key at
    # each insert, and the passes and the emitters put names in Hashes all
    # the time: frozen names make wasm's local assignment 15% faster.
    # `Marshal.load(bytes, INTERNED)` interns the names of loaded IR; it
    # leaves binary Strings (code bytes) as they are.
    INTERNED = ->(object) { object.instance_of?(String) && object.encoding != Encoding::BINARY ? -object : object }

    # The records' types are in sig/zr/ir/function.rbs.
    # @rbs skip
    Slot = Struct.new(:bytes, :align)
    # @rbs skip
    Global = Data.define(:gv, :symbol, :colocated)
    # @rbs skip
    Sig = Data.define(:sig, :params, :ret)
    # `from`: the wasm module an imported callee comes from, or nil.
    # `effects`: the `IR::Effects` bits that a call can write.
    # @rbs skip
    Callee = Struct.new(:fn, :symbol, :sig, :colocated, :from, :effects)

    # A basic block: its parameters as `[value, type]` pairs, and its
    # instructions in order.
    class Block
      attr_reader :name #: String
      attr_reader :params #: Array[[String, String]]
      attr_reader :insts #: Array[Inst]
      # A block that runs rarely (a slow path: a miss, an overflow, a
      # poll that fired). The backend puts it after the other blocks, so
      # the common path falls through and fetches no taken branch.
      attr_accessor :cold #: bool?

      #: (String name, Array[[String, String]] params) -> void
      def initialize(name, params)
        @name = name
        @params = params
        @insts = []
      end

      #: () -> bool
      def terminated?
        !@insts.empty? && @insts.last.terminator?
      end
    end

    # A function under construction: its stack slots, the symbols and
    # callees that it uses, and its blocks in layout order. The function
    # numbers its values and blocks, so it is in SSA form by construction.
    class Function
      # @rbs @entry: String
      # @rbs @global_of: Hash[String, String]
      # @rbs @sig_of: Hash[[Array[String], String?], String]
      # @rbs @callee_of: Hash[String, String]
      # @rbs @block_of: Hash[String, Block]
      # @rbs @next_block: Integer
      # @rbs @hoisted: Hash[Symbol, Hash[untyped, String]]
      # @rbs @iconst_of: Hash[String, Integer]
      # @rbs @next_value: Integer
      # @rbs @analysis: Analysis?

      # `current` is the block that gets new instructions. A caller that
      # fills a block out of order needs it to resume. `initialize` makes
      # the entry block current, so both are a Block after it.
      attr_reader :name #: String
      attr_reader :params #: Array[String]
      attr_reader :ret_type #: String?
      attr_reader :args #: Array[String]
      attr_reader :current #: Block
      attr_reader :slots #: Array[Slot]
      attr_reader :globals #: Array[Global]
      attr_reader :sigs #: Array[Sig]
      attr_reader :callees #: Array[Callee]
      attr_reader :blocks #: Array[Block]
      attr_reader :entry_block #: Block

      # `params`/`ret`: IR types. The entry block takes the parameters
      # as v0..vN-1. A `ret` of nil returns nothing.
      #: (String name, Array[String] params, String? ret) -> void
      def initialize(name, params, ret)
        reset(name, params, ret)
        @args = params.map { value }
        pairs = @args.zip(params) #: Array[[String, String]]
        @entry = block_named(pairs)
        switch(@entry)
      end

      # A new stack slot of `bytes`.
      #: (Integer bytes) -> String
      def slot(bytes)
        @slots << Slot.new(bytes, 8)
        "ss#{@slots.size - 1}"
      end

      # The global value that refers to `symbol`.
      #: (String symbol, ?colocated: bool) -> String
      def symbol(symbol, colocated: true)
        @global_of[symbol] ||= begin
          gv = "gv#{@globals.size}"
          @globals << Global.new(gv, symbol, colocated)
          gv
        end
      end

      # A function that this program defines, or that it imports `from` a
      # wasm module. `effects` is what a call can write: all regions, unless
      # the kernel description gives less.
      #: (String symbol, Array[String] params, String? ret, ?colocated: bool, ?from: String?, ?effects: Integer) -> String
      def callee(symbol, params, ret, colocated: true, from: nil, effects: Effects::ALL)
        @callee_of[symbol] ||= begin
          sig = signature(params, ret)
          fn = "fn#{@callees.size}"
          @callees << Callee.new(fn, symbol, sig, colocated, from, effects)
          fn
        end
      end

      # A new block. `params` are IR types. Returns the block name and its
      # parameter values.
      #: (?Array[String] params) -> [String, Array[String]]
      def block(params = [])
        values = params.map { value }
        pairs = values.zip(params) #: Array[[String, String]]
        [block_named(pairs), values]
      end

      # A block with no parameters, by name only.
      #: () -> String
      def label
        block.first
      end

      # Marks the block `label` as a slow path (`Block#cold`).
      #: (String label) -> String
      def cold(label)
        @block_of.fetch(label).cold = true
        label
      end

      # Continues to emit into `block`. The current block must end in a jump,
      # a branch or a return, unless the caller will `finish` it later.
      #: (String block, ?open: bool) -> void
      def switch(block, open: false)
        raise "#{@current.name} of #{@name} was left without a terminator" if @current && !open && !@current.terminated?

        @current = @block_of.fetch(block)
        @blocks << @current
      end

      # The terminator of a block left open by `switch(open: true)`.
      #: (String block, Inst inst) -> nil
      def finish(block, inst)
        b = @block_of.fetch(block)
        raise "#{block} of #{@name} already has a terminator" if b.terminated?

        b.insts << inst
        nil
      end

      # Whether the current block has already ended.
      #: () -> bool
      def terminated?
        @current.terminated?
      end

      # A call with no result.
      #: (String fn, ?Array[String] args) -> nil
      def call(fn, args = [])
        emit(Inst.new(:call, callee: fn, args: args))
        nil
      end

      # A call with one result, which this returns.
      #: (String fn, ?Array[String] args) -> String
      def call_val(fn, args = [])
        v = value
        emit(Inst.new(:call, results: [v], callee: fn, args: args))
        v
      end

      # A call through `ptr` with the signature `sig`, with no result.
      #: (String sig, String ptr, ?Array[String] args) -> nil
      def call_indirect(sig, ptr, args = [])
        emit(Inst.new(:call_indirect, callee: sig, args: [ptr] + args))
        nil
      end

      # A call through `ptr` with one result, which this returns.
      #: (String sig, String ptr, ?Array[String] args) -> String
      def call_indirect_val(sig, ptr, args = [])
        v = value
        emit(Inst.new(:call_indirect, results: [v], callee: sig, args: [ptr] + args))
        v
      end

      # The signature `params -> ret`, made one time for each function.
      #: (Array[String] params, String? ret) -> String
      def sig(params, ret)
        signature(params, ret)
      end

      # An unconditional jump that passes `args` to the target block params.
      #: (String block, ?Array[String] args) -> nil
      def jump(block, args = [])
        emit(Inst.new(:jump, targets: [[block, args]]))
        nil
      end

      # A branch on `cond`: to `a` when it is true, to `b` if not.
      #: (String cond, String a, String b) -> nil
      def brif(cond, a, b)
        emit(Inst.new(:brif, args: [cond], targets: [[a, []], [b, []]]))
        nil
      end

      # A jump table on `value`: to the block of its key in `cases`
      # (`{ key => block }`, each key masked to the value's type), else to
      # `default`.
      #: (String value, Hash[Integer, String] cases, String default) -> nil
      def table(value, cases, default)
        keys = cases.keys.sort
        emit(Inst.new(:switch, args: [value, *keys], targets: [[default, []], *keys.map { |k| [cases.fetch(k), []] }]))
        nil
      end

      # A return, with or without a value.
      #: (?String? value) -> nil
      def ret(value = nil)
        emit(Inst.new(:return, args: value.nil? ? [] : [value]))
        nil
      end

      # A store of `value` to `addr` (+`offset`), with no trap and aligned.
      # The lowering never writes other flags. `region` is the
      # `IR::Effects` region of the word, when the lowering knows it.
      # `region` is a Symbol, because `Machine::Lower` selects it in a
      # local that Steep types as a Symbol.
      #: (String value, String addr, ?Integer offset, ?region: Symbol?) -> nil
      def store(value, addr, offset = 0, region: nil)
        known = region #: region?
        emit(Inst.new(:store, args: [value, addr], offset: offset, flags: "notrap aligned", region: known))
        nil
      end

      # A load of `type` from `addr` (+`offset`); returns the value. The name
      # is `fetch`, not `load`, because `Kernel#load` exists.
      #: (String type, String addr, ?Integer offset, ?region: region?) -> String
      def fetch(type, addr, offset = 0, region: nil)
        v = value
        emit(Inst.new(:load, type: type, results: [v], args: [addr], offset: offset, flags: "notrap aligned",
                      region: region))
        v
      end

      # An integer comparison; `cond` is the IR's spelling (`"ne"`, `"eq"`, ...).
      #: (String cond, String a, String b) -> String
      def icmp(cond, a, b)
        v = value
        emit(Inst.new(:icmp, results: [v], cond: cond, args: [a, b]))
        v
      end

      #: (String a, String b, ?type: String?) -> String
      def iadd(a, b, type: nil)
        v = value
        emit(Inst.new(:iadd, type: type, results: [v], args: [a, b]))
        v
      end

      #: (String a, String b, ?type: String?) -> String
      def isub(a, b, type: nil)
        v = value
        emit(Inst.new(:isub, type: type, results: [v], args: [a, b]))
        v
      end

      #: (String a, String b, ?type: String?) -> String
      def band(a, b, type: nil)
        v = value
        emit(Inst.new(:band, type: type, results: [v], args: [a, b]))
        v
      end

      #: (String a, String b, ?type: String?) -> String
      def bor(a, b, type: nil)
        v = value
        emit(Inst.new(:bor, type: type, results: [v], args: [a, b]))
        v
      end

      # The other two-operand integer instructions, by opcode. `op` is a
      # Symbol, because `Machine::Lower` makes it from an operator. This
      # checks it, and then it is an `op`.
      #: (Symbol op, String a, String b, ?type: String?) -> String
      def binop(op, a, b, type: nil)
        code = op #: IR::op
        raise ArgumentError, "not a binary opcode: #{op}" unless Inst::BINOPS.include?(code)

        v = value
        emit(Inst.new(code, type: type, results: [v], args: [a, b]))
        v
      end

      # The one-operand integer instructions, by opcode: `ctz`, `clz`,
      # `popcnt`, `bswap`, as wide as `a`.
      #: (op op, String a) -> String
      def bitop(op, a)
        raise ArgumentError, "not a bit opcode: #{op}" unless Inst::BITOPS.include?(op)

        v = value
        emit(Inst.new(op, results: [v], args: [a]))
        v
      end

      # The f64 instructions: arithmetic, one-operand math, comparison
      # (an i8), and the conversions to and from i64.
      # `op` is a Symbol for the reason in `binop`.
      #: (Symbol op, String a, String b) -> String
      def fbinop(op, a, b)
        code = op #: IR::op
        raise ArgumentError, "not an f64 binary opcode: #{op}" unless Inst::FBINOPS.include?(code)

        v = value
        emit(Inst.new(code, results: [v], args: [a, b]))
        v
      end

      #: (op op, String a) -> String
      def funop(op, a)
        raise ArgumentError, "not an f64 unary opcode: #{op}" unless Inst::FUNOPS.include?(op)

        v = value
        emit(Inst.new(op, results: [v], args: [a]))
        v
      end

      #: (String cond, String a, String b) -> String
      def fcmp(cond, a, b)
        raise ArgumentError, "not an fcmp condition: #{cond}" unless Inst::FCONDS.include?(cond)

        v = value
        emit(Inst.new(:fcmp, results: [v], cond: cond, args: [a, b]))
        v
      end

      #: (String a) -> String
      def fcvt_from_sint(a)
        v = value
        emit(Inst.new(:fcvt_from_sint, type: "f64", results: [v], args: [a]))
        v
      end

      #: (String a) -> String
      def fcvt_to_sint_sat(a)
        v = value
        emit(Inst.new(:fcvt_to_sint_sat, type: "i64", results: [v], args: [a]))
        v
      end

      # A narrowing, and the two widenings. `type` is the result type.
      #: (String type, String a) -> String
      def ireduce(type, a) = width(:ireduce, type, a)
      #: (String type, String a) -> String
      def sextend(type, a) = width(:sextend, type, a)
      #: (String type, String a) -> String
      def uextend(type, a) = width(:uextend, type, a)

      #: (op op, String type, String a) -> String
      def width(op, type, a)
        v = value
        emit(Inst.new(op, type: type, results: [v], args: [a]))
        v
      end

      # The same bits as the other type: `type` is "f64" or "i64".
      #: (String type, String a) -> String
      def bitcast(type, a)
        v = value
        emit(Inst.new(:bitcast, type: type, results: [v], args: [a]))
        v
      end

      #: (String a, String b) -> String
      def imul(a, b) = binop(:imul, a, b)
      #: (String a, String b) -> String
      def bxor(a, b) = binop(:bxor, a, b)
      #: (String a, String b) -> String
      def ishl(a, b) = binop(:ishl, a, b)
      #: (String a, String b) -> String
      def ushr(a, b) = binop(:ushr, a, b)
      #: (String a, String b) -> String
      def sshr(a, b) = binop(:sshr, a, b)
      #: (String a, String b) -> String
      def sdiv(a, b) = binop(:sdiv, a, b)
      #: (String a, String b) -> String
      def udiv(a, b) = binop(:udiv, a, b)
      #: (String a, String b) -> String
      def srem(a, b) = binop(:srem, a, b)
      #: (String a, String b) -> String
      def urem(a, b) = binop(:urem, a, b)

      # The IR `select`. The name is `csel` because `Kernel#select` exists.
      #: (String cond, String a, String b) -> String
      def csel(cond, a, b)
        v = value
        emit(Inst.new(:select, results: [v], args: [cond, a, b]))
        v
      end

      #: (String a, String b) -> [String, String]
      def sadd_overflow(a, b) = pair_overflow(:sadd_overflow, a, b)
      #: (String a, String b) -> [String, String]
      def ssub_overflow(a, b) = pair_overflow(:ssub_overflow, a, b)
      #: (String a, String b) -> [String, String]
      def smul_overflow(a, b) = pair_overflow(:smul_overflow, a, b)

      #: (String gv) -> String
      def symbol_value(gv)
        v = value
        emit(Inst.new(:symbol_value, type: "i64", results: [v], args: [gv]))
        v
      end

      # The address of a data symbol, made one time for each function, for a
      # word that the function reads many times.
      #: (String gv) -> String
      def symbol_addr(gv)
        hoisted(:symbol_value, gv) { Inst.new(:symbol_value, type: "i64", args: [gv]) }
      end

      # A load made one time for each function, for a word that does not
      # change while the function runs (for example a pooled symbol id of a
      # unit). The load goes in the entry block, which dominates all other
      # blocks, so the value is available at each use.
      #: (String type, String addr, ?Integer offset, ?region: region?) -> String
      def hoisted_fetch(type, addr, offset = 0, region: nil)
        hoisted(:hoisted_fetch, [addr, offset]) do
          Inst.new(:load, type: type, args: [addr], offset: offset, flags: "notrap aligned", region: region)
        end
      end

      #: (String fn) -> String
      def func_addr(fn)
        v = value
        emit(Inst.new(:func_addr, type: "i64", results: [v], args: [fn]))
        v
      end

      # Reads the gate word from its register.
      #: () -> String
      def gates
        v = value
        emit(Inst.new(:gates, type: "i64", results: [v]))
        v
      end

      # Puts `word` in the gate word register. A writer calls this after it
      # stores the word. `enter` calls it at entry from foreign code; at
      # return, the register gets back the value of the foreign code.
      #: (String word) -> nil
      def gates_set(word)
        emit(Inst.new(:gates_set, args: [word]))
        nil
      end

      #: (String word) -> nil
      def gates_enter(word)
        emit(Inst.new(:gates_enter, args: [word]))
        nil
      end

      # The address of a C va_list of the function's variadic arguments,
      # in the slot `slot`, which the prologue fills as the C ABI `kind`
      # passes them (Machine::Function::VA_LIST_KINDS): 0, darwin arm64's,
      # the address of the first argument on the stack; 1, AAPCS64's
      # struct, with the save areas of x0-x7 and d0-d7 after it. Only the
      # function's own frame knows them, so a function with one is never
      # inlined. `offset` holds the kind.
      #: (String slot, Integer kind) -> String
      def va_list(slot, kind)
        v = value
        emit(Inst.new(:va_list, type: "i64", args: [slot], offset: kind, results: [v]))
        v
      end

      # A constant whose immediate a producer sets later. Returns the value,
      # and the instruction whose first argument to set.
      #: (String type) -> [String, Inst]
      def iconst_later(type)
        v = value
        inst = Inst.new(:iconst, type: type, results: [v], args: [0])
        emit(inst)
        [v, inst]
      end

      # A constant, made one time for each function.
      #: (String type, Integer n) -> String
      def iconst(type, n)
        v = hoisted(ICONST.fetch(type), n) { Inst.new(:iconst, type: type, args: [n]) }
        @iconst_of[v] = n
        v
      end

      # The immediate in `v` when `v` came from `iconst`, or nil. The function
      # knows its own constants because it made them. `Passes::Fold` finds
      # the same data from the instructions; a lowering does not need to.
      #: (String v) -> Integer?
      def iconst_of(v) = @iconst_of[v]

      # A value that is the same at all uses, defined one time in the entry
      # block.
      #
      # The entry block dominates all other blocks, so one definition there
      # is valid for uses in any block. It goes before the terminator of the
      # entry block; no use can come before it, because this is the first
      # request for the key. The block yields an `Inst` with no result; this
      # method sets the result and inserts the instruction.
      #: (Symbol kind, untyped key) { () -> Inst } -> String
      def hoisted(kind, key)
        ((@hoisted[kind] ||= {})[key] ||= begin
          v = value
          inst = yield
          inst.results = [v]
          insts = @entry_block.insts
          at = insts.size
          at -= 1 if at.positive? && insts.last.terminator?
          insts.insert(at, inst)
          v
        end)
      end

      # One hash for each kind, so a lookup uses the constant number and not
      # a new Array for each use. The four types are listed here so `iconst`
      # also needs no Array.
      ICONST = { "i8" => :iconst_i8, "i32" => :iconst_i32,
                 "i64" => :iconst_i64, "f64" => :iconst_f64 }.freeze

      # The address of a stack slot, made one time for each function.
      #: (String slot) -> String
      def stack_addr(slot)
        hoisted(:stack_addr, slot) { Inst.new(:stack_addr, type: "i64", args: [slot]) }
      end

      # Places the blocks of `placed`, in their order, just before the block
      # whose name is their key, in one pass over the blocks: a pass that
      # makes many blocks does not shift the list once for each.
      #: (Hash[String, Array[Block]] placed) -> void
      def place_before(placed)
        blocks = [] #: Array[Block]
        @blocks.each do |b|
          before = placed[b.name]
          blocks.concat(before) if before
          blocks << b
        end
        @blocks = blocks
      end

      # Places `blocks`, in their order, just after `anchor`.
      #: (Block anchor, Array[Block] blocks) -> void
      def place_after(anchor, blocks)
        at = @blocks.index(anchor) or raise ArgumentError, "#{@name}: #{anchor.name} is not in the function"
        @blocks.insert(at + 1, *blocks)
      end

      # A new block with no parameters that is not in `blocks` yet. The pass
      # places it (`place_before`, `place_after`).
      #: () -> Block
      def unplaced_block = @block_of.fetch(block_named([]))

      # A value name that no instruction uses. A pass on a finished function
      # uses it for a new block parameter.
      #: () -> String
      def value
        v = -"v#{@next_value}"
        @next_value += 1
        v
      end

      # The shape of the function for the passes (predecessors, order,
      # dominators, uses, loops). It is calculated one time and kept until a
      # pass reports a change. See `IR::Analysis`.
      #: () -> Analysis
      def analysis
        @analysis ||= Analysis.new(self)
      end

      # Whether an analysis is kept. The strict check reads this before it
      # checks the analysis against the function.
      #: () -> bool
      def analysis? = !@analysis.nil?

      # A pass that changes the function calls this: `:cfg` when it adds,
      # removes or retargets a block or an edge, `:insts` when it changes
      # only instructions. The strict check rejects a kept analysis when a
      # change was not reported.
      #: (Symbol what) -> self
      def changed!(what)
        case what
        when :cfg then @analysis = nil
        when :insts then @analysis&.insts_changed!
        else raise ArgumentError, "changed!(:cfg) or changed!(:insts), not #{what.inspect}"
        end
        self
      end

      private

      #: (String name, Array[String] params, String? ret) -> void
      def reset(name, params, ret)
        @name = name
        @params = params
        @ret_type = ret
        @slots = []
        @globals = []
        @global_of = {}
        @sigs = []
        @sig_of = {}
        @callees = []
        @callee_of = {}
        @blocks = []
        @block_of = {}
        @next_block = 0
        @hoisted = {}
        @iconst_of = {}
        @next_value = 0
        @current = nil #: untyped
        @args = []
        @analysis = nil
      end

      # An instruction after the terminator of the current block is a bug in
      # the lowering. This is the only method that appends an instruction.
      #: (Inst inst) -> void
      def emit(inst)
        raise "an instruction after the terminator of #{@current.name} in #{@name}" if @current.terminated?

        @current.insts << inst
      end

      #: (op op, String a, String b) -> [String, String]
      def pair_overflow(op, a, b)
        lo = value
        hi = value
        emit(Inst.new(op, results: [lo, hi], args: [a, b]))
        [lo, hi]
      end

      #: (Array[[String, String]] params) -> String
      def block_named(params)
        name = -"block#{@next_block}"
        @next_block += 1
        b = Block.new(name, params)
        @block_of[name] = b
        @entry_block ||= b
        name
      end

      #: (Array[String] params, String? ret) -> String
      def signature(params, ret)
        key = [params, ret] #: [Array[String], String?]
        @sig_of[key] ||= begin
          sig = "sig#{@sigs.size}"
          @sigs << Sig.new(sig, params, ret)
          sig
        end
      end
    end
  end
end
