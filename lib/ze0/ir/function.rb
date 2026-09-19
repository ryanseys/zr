# frozen_string_literal: true

require_relative "inst"

module Ze0
  module IR
    # The most parameters a function has and the most arguments a call
    # takes: eight, where every native target runs out of argument
    # registers. Every lowering keeps a signature to eight, so no backend
    # needs a stack argument path.
    REGISTER_ARGS = 8

    Slot = Struct.new(:bytes, :align)
    Global = Struct.new(:gv, :symbol, :colocated)
    Sig = Struct.new(:sig, :params, :ret)
    # `from`: the wasm module an imported callee comes from, or nil.
    Callee = Struct.new(:fn, :symbol, :sig, :colocated, :from)

    # A basic block: its parameters as `[value, type]` pairs, and its
    # instructions in order.
    class Block
      attr_reader :name, :params, :insts

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
    # callees it names, and its blocks in layout order. Values and blocks
    # are numbered here so the function is in SSA form by construction.
    class Function
      # `current` is the block being emitted into: what a caller needs when
      # it fills a block out of order and then resumes.
      attr_reader :name, :params, :ret_type, :args, :current, :slots, :globals, :sigs, :callees, :blocks, :entry_block

      # `params`/`ret`: IR types. The entry block takes the parameters
      # as v0..vN-1.
      def initialize(name, params, ret)
        reset(name, params, ret)
        @args = params.map { value }
        @entry = block_named(@args.zip(params))
        switch(@entry)
      end

      # A fresh stack slot of `bytes`.
      def slot(bytes)
        @slots << Slot.new(bytes, 8)
        "ss#{@slots.size - 1}"
      end

      # The global value naming `symbol`.
      def symbol(symbol, colocated: true)
        @global_of[symbol] ||= begin
          gv = "gv#{@globals.size}"
          @globals << Global.new(gv, symbol, colocated)
          gv
        end
      end

      # A function this program defines, or one it imports `from` a wasm
      # module.
      def callee(symbol, params, ret, colocated: true, from: nil)
        @callee_of[symbol] ||= begin
          sig = signature(params, ret)
          fn = "fn#{@callees.size}"
          @callees << Callee.new(fn, symbol, sig, colocated, from)
          fn
        end
      end

      # A new block; `params` are IR types, and the block's parameter
      # values are answered beside its name.
      def block(params = [])
        values = params.map { value }
        [block_named(values.zip(params)), values]
      end

      # A block taking no parameters, by name alone.
      def label
        block.first
      end

      # Continue emitting into `block`. The block being left must have
      # ended in a jump, a branch or a return, unless the caller says it
      # will `finish` it later.
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

      # A call with one result, answered.
      def call_val(fn, args = [])
        v = value
        emit(Inst.new(:call, results: [v], callee: fn, args: args))
        v
      end

      # A call through `ptr` with the signature `sig` names, no result.
      def call_indirect(sig, ptr, args = [])
        emit(Inst.new(:call_indirect, callee: sig, args: [ptr] + args))
        nil
      end

      # A call through `ptr`, its one result answered.
      def call_indirect_val(sig, ptr, args = [])
        v = value
        emit(Inst.new(:call_indirect, results: [v], callee: sig, args: [ptr] + args))
        v
      end

      # The signature `params -> ret`, named once per function.
      def sig(params, ret)
        signature(params, ret)
      end

      # An unconditional jump, carrying `args` to the target block's params.
      def jump(block, args = [])
        emit(Inst.new(:jump, targets: [[block, args]]))
        nil
      end

      # A branch on `cond`: to `a` when it holds, `b` otherwise.
      def brif(cond, a, b)
        emit(Inst.new(:brif, args: [cond], targets: [[a, []], [b, []]]))
        nil
      end

      # A return, with or without a value.
      def ret(value = nil)
        emit(Inst.new(:return, args: value.nil? ? [] : [value]))
        nil
      end

      # A store of `value` to `addr` (+`offset`), untrapped and aligned: the
      # only flags the lowering ever writes.
      def store(value, addr, offset = 0)
        emit(Inst.new(:store, args: [value, addr], offset: offset, flags: "notrap aligned"))
        nil
      end

      # A load of `type` from `addr` (+`offset`), answered. Named `fetch`,
      # not `load`: `Kernel#load` already exists.
      def fetch(type, addr, offset = 0)
        v = value
        emit(Inst.new(:load, type: type, results: [v], args: [addr], offset: offset, flags: "notrap aligned"))
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

      # A narrowing, and the two widenings: `type` is the type answered.
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

      # The IR's `select`; named `csel` because `Kernel#select` already exists.
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

      # The address of a data symbol, materialized once per function: for
      # a word that the function reads again and again.
      def symbol_addr(gv)
        hoisted(:symbol_value, gv) { Inst.new(:symbol_value, type: "i64", args: [gv]) }
      end

      # A load materialized once per function: a word that never changes
      # while the function runs, such as one of a unit's pooled symbol
      # ids. It stands in the entry block, which dominates every other,
      # so the value is in scope wherever the lowering wants it -- as an
      # immediate was before the link started numbering the symbols.
      def hoisted_fetch(type, addr, offset = 0)
        hoisted(:hoisted_fetch, [addr, offset]) do
          Inst.new(:load, type: type, args: [addr], offset: offset, flags: "notrap aligned")
        end
      end

      def func_addr(fn)
        v = value
        emit(Inst.new(:func_addr, type: "i64", results: [v], args: [fn]))
        v
      end

      # A constant whose immediate a producer fills in later: the value,
      # and the instruction whose first argument to set.
      def iconst_later(type)
        v = value
        inst = Inst.new(:iconst, type: type, results: [v], args: [0])
        emit(inst)
        [v, inst]
      end

      # A constant, materialized once per function.
      def iconst(type, n)
        v = hoisted(ICONST.fetch(type), n) { Inst.new(:iconst, type: type, args: [n]) }
        @iconst_of[v] = n
        v
      end

      # The immediate `v` holds, where `v` came from `iconst`, and nil
      # where it came from anything else. A function knows its own
      # constants because it made them; `Passes::Fold` walks the
      # instructions to learn the same thing, which a lowering has no
      # reason to do.
      def iconst_of(v) = @iconst_of[v]

      # A value that is the same everywhere, defined once in the entry block.
      #
      # The entry block dominates every other block, so a value defined there
      # is in scope for all of them, which is what makes one definition legal
      # where the uses are scattered. It goes in ahead of the entry block's
      # terminator, and no use can be earlier: this is the first time the key
      # has been asked for. The block yields an `Inst` with no result; this
      # fills one in and inserts it.
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

      # A bucket a kind, so a constant is found by its own number rather
      # than by an Array built and hashed at every mention of it. The four
      # types are named here so that `iconst` needs no Array either.
      ICONST = { "i8" => :iconst_i8, "i32" => :iconst_i32,
                 "i64" => :iconst_i64, "f64" => :iconst_f64 }.freeze

      # The address of a stack slot, materialized once per function.
      def stack_addr(slot)
        hoisted(:stack_addr, slot) { Inst.new(:stack_addr, type: "i64", args: [slot]) }
      end

      # A new block with no parameters, laid out right after `after`: what
      # a pass makes when it splits a block, so the first half falls into
      # it.
      def block_after(after) = block_beside(@blocks.index(after) + 1)

      # The same, laid out right before `before`: what a pass makes when
      # it splits an edge, so the new block falls into its target.
      def block_before(before) = block_beside(@blocks.index(before))

      def block_beside(at)
        b = @block_of.fetch(block_named([]))
        @blocks.insert(at, b)
        b
      end

      # A value name no instruction has used: what a pass over the finished
      # function names a new block parameter with.
      def value
        v = "v#{@next_value}"
        @next_value += 1
        v
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
      end

      # An instruction after the current block's terminator is a bug in the
      # lowering, never a legal program: this is the one place that appends.
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
