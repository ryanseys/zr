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

    Slot = Struct.new(:bytes, :align)
    Global = Data.define(:gv, :symbol, :colocated)
    Sig = Data.define(:sig, :params, :ret)
    # `from`: the wasm module an imported callee comes from, or nil.
    # `effects`: the `IR::Effects` bits that a call can write.
    Callee = Struct.new(:fn, :symbol, :sig, :colocated, :from, :effects)

    # A basic block: its parameters as `[value, type]` pairs, and its
    # instructions in order.
    class Block
      attr_reader :name, :params, :insts
      # A block that runs rarely (a slow path: a miss, an overflow, a
      # poll that fired). The backend puts it after the other blocks, so
      # the common path falls through and fetches no taken branch.
      attr_accessor :cold

      def initialize(name, params)
        @name = name
        @params = params
        @insts = []
      end

      def terminated?
        !@insts.empty? && @insts.last.terminator?
      end
    end

    # A function under construction: its stack slots, the symbols and
    # callees that it uses, and its blocks in layout order. The function
    # numbers its values and blocks, so it is in SSA form by construction.
    class Function
      # `current` is the block that gets new instructions. A caller that
      # fills a block out of order needs it to resume.
      attr_reader :name, :params, :ret_type, :args, :current, :slots, :globals, :sigs, :callees, :blocks, :entry_block

      # `params`/`ret`: IR types. The entry block takes the parameters
      # as v0..vN-1.
      def initialize(name, params, ret)
        reset(name, params, ret)
        @args = params.map { value }
        @entry = block_named(@args.zip(params))
        switch(@entry)
      end

      # A new stack slot of `bytes`.
      def slot(bytes)
        @slots << Slot.new(bytes, 8)
        "ss#{@slots.size - 1}"
      end

      # The global value that refers to `symbol`.
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
      def block(params = [])
        values = params.map { value }
        [block_named(values.zip(params)), values]
      end

      # A block with no parameters, by name only.
      def label
        block.first
      end

      # Marks the block `label` as a slow path (`Block#cold`).
      def cold(label)
        @block_of.fetch(label).cold = true
        label
      end

      # Continues to emit into `block`. The current block must end in a jump,
      # a branch or a return, unless the caller will `finish` it later.
      def switch(block, open: false)
        raise "#{@current.name} of #{@name} was left without a terminator" if @current && !open && !@current.terminated?

        @current = @block_of.fetch(block)
        @blocks << @current
      end

      # The terminator of a block left open by `switch(open: true)`.
      def finish(block, inst)
        b = @block_of.fetch(block)
        raise "#{block} of #{@name} already has a terminator" if b.terminated?

        b.insts << inst
        nil
      end

      # Whether the current block has already ended.
      def terminated?
        @current.terminated?
      end

      # A call with no result.
      def call(fn, args = [])
        emit(Inst.new(:call, callee: fn, args: args))
        nil
      end

      # A call with one result, which this returns.
      def call_val(fn, args = [])
        v = value
        emit(Inst.new(:call, results: [v], callee: fn, args: args))
        v
      end

      # A call through `ptr` with the signature `sig`, with no result.
      def call_indirect(sig, ptr, args = [])
        emit(Inst.new(:call_indirect, callee: sig, args: [ptr] + args))
        nil
      end

      # A call through `ptr` with one result, which this returns.
      def call_indirect_val(sig, ptr, args = [])
        v = value
        emit(Inst.new(:call_indirect, results: [v], callee: sig, args: [ptr] + args))
        v
      end

      # The signature `params -> ret`, made one time for each function.
      def sig(params, ret)
        signature(params, ret)
      end

      # An unconditional jump that passes `args` to the target block params.
      def jump(block, args = [])
        emit(Inst.new(:jump, targets: [[block, args]]))
        nil
      end

      # A branch on `cond`: to `a` when it is true, to `b` if not.
      def brif(cond, a, b)
        emit(Inst.new(:brif, args: [cond], targets: [[a, []], [b, []]]))
        nil
      end

      # A jump table on `value`: to the block of its key in `cases`
      # (`{ key => block }`, each key masked to the value's type), else to
      # `default`.
      def table(value, cases, default)
        keys = cases.keys.sort
        emit(Inst.new(:switch, args: [value, *keys], targets: [[default, []], *keys.map { |k| [cases.fetch(k), []] }]))
        nil
      end

      # A return, with or without a value.
      def ret(value = nil)
        emit(Inst.new(:return, args: value.nil? ? [] : [value]))
        nil
      end

      # A store of `value` to `addr` (+`offset`), with no trap and aligned.
      # The lowering never writes other flags. `region` is the
      # `IR::Effects` region of the word, when the lowering knows it.
      def store(value, addr, offset = 0, region: nil)
        emit(Inst.new(:store, args: [value, addr], offset: offset, flags: "notrap aligned", region: region))
        nil
      end

      # A load of `type` from `addr` (+`offset`); returns the value. The name
      # is `fetch`, not `load`, because `Kernel#load` exists.
      def fetch(type, addr, offset = 0, region: nil)
        v = value
        emit(Inst.new(:load, type: type, results: [v], args: [addr], offset: offset, flags: "notrap aligned",
                      region: region))
        v
      end

      # An integer comparison; `cond` is the IR's spelling (`"ne"`, `"eq"`, ...).
      def icmp(cond, a, b)
        v = value
        emit(Inst.new(:icmp, results: [v], cond: cond, args: [a, b]))
        v
      end

      def iadd(a, b, type: nil)
        v = value
        emit(Inst.new(:iadd, type: type, results: [v], args: [a, b]))
        v
      end

      def isub(a, b, type: nil)
        v = value
        emit(Inst.new(:isub, type: type, results: [v], args: [a, b]))
        v
      end

      def band(a, b, type: nil)
        v = value
        emit(Inst.new(:band, type: type, results: [v], args: [a, b]))
        v
      end

      def bor(a, b, type: nil)
        v = value
        emit(Inst.new(:bor, type: type, results: [v], args: [a, b]))
        v
      end

      # The other two-operand integer instructions, by opcode.
      def binop(op, a, b, type: nil)
        raise ArgumentError, "not a binary opcode: #{op}" unless Inst::BINOPS.include?(op)

        v = value
        emit(Inst.new(op, type: type, results: [v], args: [a, b]))
        v
      end

      # The one-operand integer instructions, by opcode: `ctz`, `clz`,
      # `popcnt`, `bswap`, as wide as `a`.
      def bitop(op, a)
        raise ArgumentError, "not a bit opcode: #{op}" unless Inst::BITOPS.include?(op)

        v = value
        emit(Inst.new(op, results: [v], args: [a]))
        v
      end

      # The f64 instructions: arithmetic, one-operand math, comparison
      # (an i8), and the conversions to and from i64.
      def fbinop(op, a, b)
        raise ArgumentError, "not an f64 binary opcode: #{op}" unless Inst::FBINOPS.include?(op)

        v = value
        emit(Inst.new(op, results: [v], args: [a, b]))
        v
      end

      def funop(op, a)
        raise ArgumentError, "not an f64 unary opcode: #{op}" unless Inst::FUNOPS.include?(op)

        v = value
        emit(Inst.new(op, results: [v], args: [a]))
        v
      end

      def fcmp(cond, a, b)
        raise ArgumentError, "not an fcmp condition: #{cond}" unless Inst::FCONDS.include?(cond)

        v = value
        emit(Inst.new(:fcmp, results: [v], cond: cond, args: [a, b]))
        v
      end

      def fcvt_from_sint(a)
        v = value
        emit(Inst.new(:fcvt_from_sint, type: "f64", results: [v], args: [a]))
        v
      end

      def fcvt_to_sint_sat(a)
        v = value
        emit(Inst.new(:fcvt_to_sint_sat, type: "i64", results: [v], args: [a]))
        v
      end

      # A narrowing, and the two widenings. `type` is the result type.
      def ireduce(type, a) = width(:ireduce, type, a)
      def sextend(type, a) = width(:sextend, type, a)
      def uextend(type, a) = width(:uextend, type, a)

      def width(op, type, a)
        v = value
        emit(Inst.new(op, type: type, results: [v], args: [a]))
        v
      end

      # The same bits as the other type: `type` is "f64" or "i64".
      def bitcast(type, a)
        v = value
        emit(Inst.new(:bitcast, type: type, results: [v], args: [a]))
        v
      end

      def imul(a, b) = binop(:imul, a, b)
      def bxor(a, b) = binop(:bxor, a, b)
      def ishl(a, b) = binop(:ishl, a, b)
      def ushr(a, b) = binop(:ushr, a, b)
      def sshr(a, b) = binop(:sshr, a, b)
      def sdiv(a, b) = binop(:sdiv, a, b)
      def udiv(a, b) = binop(:udiv, a, b)
      def srem(a, b) = binop(:srem, a, b)
      def urem(a, b) = binop(:urem, a, b)

      # The IR `select`. The name is `csel` because `Kernel#select` exists.
      def csel(cond, a, b)
        v = value
        emit(Inst.new(:select, results: [v], args: [cond, a, b]))
        v
      end

      def sadd_overflow(a, b) = pair_overflow(:sadd_overflow, a, b)
      def ssub_overflow(a, b) = pair_overflow(:ssub_overflow, a, b)
      def smul_overflow(a, b) = pair_overflow(:smul_overflow, a, b)

      def symbol_value(gv)
        v = value
        emit(Inst.new(:symbol_value, type: "i64", results: [v], args: [gv]))
        v
      end

      # The address of a data symbol, made one time for each function, for a
      # word that the function reads many times.
      def symbol_addr(gv)
        hoisted(:symbol_value, gv) { Inst.new(:symbol_value, type: "i64", args: [gv]) }
      end

      # A load made one time for each function, for a word that does not
      # change while the function runs (for example a pooled symbol id of a
      # unit). The load goes in the entry block, which dominates all other
      # blocks, so the value is available at each use.
      def hoisted_fetch(type, addr, offset = 0, region: nil)
        hoisted(:hoisted_fetch, [addr, offset]) do
          Inst.new(:load, type: type, args: [addr], offset: offset, flags: "notrap aligned", region: region)
        end
      end

      def func_addr(fn)
        v = value
        emit(Inst.new(:func_addr, type: "i64", results: [v], args: [fn]))
        v
      end

      # Reads the gate word from its register.
      def gates
        v = value
        emit(Inst.new(:gates, type: "i64", results: [v]))
        v
      end

      # Puts `word` in the gate word register. A writer calls this after it
      # stores the word. `enter` calls it at entry from foreign code; at
      # return, the register gets back the value of the foreign code.
      def gates_set(word)
        emit(Inst.new(:gates_set, args: [word]))
        nil
      end

      def gates_enter(word)
        emit(Inst.new(:gates_enter, args: [word]))
        nil
      end

      # A constant whose immediate a producer sets later. Returns the value,
      # and the instruction whose first argument to set.
      def iconst_later(type)
        v = value
        inst = Inst.new(:iconst, type: type, results: [v], args: [0])
        emit(inst)
        [v, inst]
      end

      # A constant, made one time for each function.
      def iconst(type, n)
        v = hoisted(ICONST.fetch(type), n) { Inst.new(:iconst, type: type, args: [n]) }
        @iconst_of[v] = n
        v
      end

      # The immediate in `v` when `v` came from `iconst`, or nil. The function
      # knows its own constants because it made them. `Passes::Fold` finds
      # the same data from the instructions; a lowering does not need to.
      def iconst_of(v) = @iconst_of[v]

      # A value that is the same at all uses, defined one time in the entry
      # block.
      #
      # The entry block dominates all other blocks, so one definition there
      # is valid for uses in any block. It goes before the terminator of the
      # entry block; no use can come before it, because this is the first
      # request for the key. The block yields an `Inst` with no result; this
      # method sets the result and inserts the instruction.
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
      def stack_addr(slot)
        hoisted(:stack_addr, slot) { Inst.new(:stack_addr, type: "i64", args: [slot]) }
      end

      # A new block with no parameters, placed just after `after`. A pass
      # uses this to split a block, so the first half falls through into it.
      def block_after(after) = block_beside(@blocks.index(after) + 1)

      # A new block placed just before `before`. A pass uses this to split an
      # edge, so the new block falls through into its target.
      def block_before(before) = block_beside(@blocks.index(before))

      def block_beside(at)
        b = unplaced_block
        @blocks.insert(at, b)
        b
      end

      # A new block with no parameters that is not in `blocks` yet. The pass
      # puts it there.
      def unplaced_block = @block_of.fetch(block_named([]))

      # A value name that no instruction uses. A pass on a finished function
      # uses it for a new block parameter.
      def value
        v = "v#{@next_value}"
        @next_value += 1
        v
      end

      # The shape of the function for the passes (predecessors, order,
      # dominators, uses, loops). It is calculated one time and kept until a
      # pass reports a change. See `IR::Analysis`.
      def analysis
        @analysis ||= Analysis.new(self)
      end

      # Whether an analysis is kept. The strict check reads this before it
      # checks the analysis against the function.
      def analysis? = !@analysis.nil?

      # A pass that changes the function calls this: `:cfg` when it adds,
      # removes or retargets a block or an edge, `:insts` when it changes
      # only instructions. The strict check rejects a kept analysis when a
      # change was not reported.
      def changed!(what)
        case what
        when :cfg then @analysis = nil
        when :insts then @analysis&.insts_changed!
        else raise ArgumentError, "changed!(:cfg) or changed!(:insts), not #{what.inspect}"
        end
        self
      end

      private

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
        @current = nil
        @args = []
        @analysis = nil
      end

      # An instruction after the terminator of the current block is a bug in
      # the lowering. This is the only method that appends an instruction.
      def emit(inst)
        raise "an instruction after the terminator of #{@current.name} in #{@name}" if @current.terminated?

        @current.insts << inst
      end

      def pair_overflow(op, a, b)
        lo = value
        hi = value
        emit(Inst.new(op, results: [lo, hi], args: [a, b]))
        [lo, hi]
      end

      def block_named(params)
        name = "block#{@next_block}"
        @next_block += 1
        b = Block.new(name, params)
        @block_of[name] = b
        @entry_block ||= b
        name
      end

      def signature(params, ret)
        key = [params, ret]
        @sig_of[key] ||= begin
          sig = "sig#{@sigs.size}"
          @sigs << Sig.new(sig, params, ret)
          sig
        end
      end
    end
  end
end
