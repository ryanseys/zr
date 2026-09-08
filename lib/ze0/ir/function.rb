# frozen_string_literal: true

require_relative "inst"
require_relative "clif_text"

module Ze0
  module IR
    Slot = Struct.new(:bytes, :align)
    Global = Struct.new(:gv, :symbol, :colocated)
    Sig = Struct.new(:sig, :params, :ret)
    Callee = Struct.new(:fn, :symbol, :sig, :colocated)

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
      attr_reader :name, :params, :ret_type, :args, :current, :slots, :globals, :sigs, :callees, :blocks

      # `params`/`ret`: CLIF types. The entry block takes the parameters
      # as v0..vN-1.
      def initialize(name, params, ret)
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
        @next_value = 0
        @current = nil
        @args = params.map { value }
        @entry = block_named(@args.zip(params))
        switch(@entry)
      end

      # A fresh stack slot of `bytes`.
      def slot(bytes = Capi::SLOT_BYTES)
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

      # A runtime entry point, by its `Capi::SIGS` row.
      def import(symbol)
        params, ret = Capi::SIGS.fetch(symbol) { raise ArgumentError, "no runtime row for #{symbol}" }
        callee(symbol, params, ret, colocated: false)
      end

      # A function this program defines.
      def callee(symbol, params, ret, colocated: true)
        @callee_of[symbol] ||= begin
          sig = signature(params, ret)
          fn = "fn#{@callees.size}"
          @callees << Callee.new(fn, symbol, sig, colocated)
          fn
        end
      end

      # A new block; `params` are CLIF types, and the block's parameter
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
      # ended in a jump, a branch or a return.
      def switch(block)
        raise "#{@current.name} of #{@name} was left without a terminator" if @current && !@current.terminated?

        @current = @block_of.fetch(block)
        @blocks << @current
      end

      # Whether the current block has already ended.
      def terminated?
        @current.terminated?
      end

      # An instruction with no result. `text` is the CLIF spelling; an
      # `Inst` is taken as it is. Kept for tests: the lowering builds `Inst`s
      # directly, through the methods below.
      def ins(text)
        emit(text.is_a?(Inst) ? text : Inst.parse(text))
        nil
      end

      # An instruction with one result, answered.
      def val(text)
        v = value
        ins("#{v} = #{text}")
        v
      end

      # An instruction with two results, answered.
      def vals(text)
        a = value
        b = value
        ins("#{a}, #{b} = #{text}")
        [a, b]
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

      # An integer comparison; `cond` is CLIF's spelling (`"ne"`, `"eq"`, ...).
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

      # CLIF's `select`; named `csel` because `Kernel#select` already exists.
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

      def func_addr(fn)
        v = value
        emit(Inst.new(:func_addr, type: "i64", results: [v], args: [fn]))
        v
      end

      # A constant, materialized once per function.
      def iconst(type, n)
        hoisted([:iconst, type, n]) { Inst.new(:iconst, type: type, args: [n]) }
      end

      # A value that is the same everywhere, defined once in the entry block.
      #
      # The entry block dominates every other block, so a value defined there
      # is in scope for all of them, which is what makes one definition legal
      # where the uses are scattered. It goes in ahead of the entry block's
      # terminator, and no use can be earlier: this is the first time the key
      # has been asked for. The block yields an `Inst` with no result; this
      # fills one in and inserts it.
      def hoisted(key)
        @hoisted[key] ||= begin
          v = value
          inst = yield
          inst.results = [v]
          insts = @entry_block.insts
          at = insts.size
          at -= 1 if at.positive? && insts.last.terminator?
          insts.insert(at, inst)
          v
        end
      end

      # The address of a stack slot, materialized once per function.
      def stack_addr(slot)
        hoisted([:stack_addr, slot]) { Inst.new(:stack_addr, type: "i64", args: [slot]) }
      end

      def to_s
        raise "#{@current.name} of #{@name} has no terminator" unless @current.terminated?

        ClifText.render(self)
      end

      private

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

      def value
        v = "v#{@next_value}"
        @next_value += 1
        v
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
