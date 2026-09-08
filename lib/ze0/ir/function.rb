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
      attr_reader :name, :params, :ret, :args, :current, :slots, :globals, :sigs, :callees, :blocks

      # `params`/`ret`: CLIF types. The entry block takes the parameters
      # as v0..vN-1.
      def initialize(name, params, ret)
        reset(name, params, ret)
        @args = params.map { value }
        @entry = block_named(@args.zip(params))
        switch(@entry)
      end

      # A function with nothing in it yet, for a parser or another producer
      # that names its own blocks and values.
      def self.bare(name, params, ret)
        f = allocate
        f.send(:reset, name, params, ret)
        f
      end

      # A block by name, as a parser names it. `params` are `[value, type]`.
      def add_block(name, params)
        b = Block.new(name, params)
        @block_of[name] = b
        @blocks << b
        @entry_block ||= b
        @current = b
        b
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
      # ended in a jump, a branch or a return, unless the caller says it
      # will `finish` it later.
      def switch(block, open: false)
        raise "#{@current.name} of #{@name} was left without a terminator" if @current && !open && !@current.terminated?

        @current = @block_of.fetch(block)
        @blocks << @current
      end

      # The terminator of a block left open by `switch(open: true)`.
      def finish(block, text)
        b = @block_of.fetch(block)
        raise "#{block} of #{@name} already has a terminator" if b.terminated?

        b.insts << (text.is_a?(Inst) ? text : Inst.parse(text))
        nil
      end

      # Whether the current block has already ended.
      def terminated?
        @current.terminated?
      end

      # An instruction with no result. `text` is the CLIF spelling today;
      # an `Inst` is taken as it is.
      def ins(text)
        raise "an instruction after the terminator of #{@current.name} in #{@name}" if @current.terminated?

        @current.insts << (text.is_a?(Inst) ? text : Inst.parse(text))
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

      # A constant, materialized once per function.
      def iconst(type, n)
        hoisted([:iconst, type, n]) { "iconst.#{type} #{n}" }
      end

      # A value that is the same everywhere, defined once in the entry block.
      #
      # The entry block dominates every other block, so a value defined there
      # is in scope for all of them, which is what makes one definition legal
      # where the uses are scattered. It goes in ahead of the entry block's
      # terminator, and no use can be earlier: this is the first time the key
      # has been asked for.
      def hoisted(key)
        @hoisted[key] ||= begin
          v = value
          insts = @entry_block.insts
          at = insts.size
          at -= 1 if at.positive? && insts.last.terminator?
          insts.insert(at, Inst.parse("#{v} = #{yield}"))
          v
        end
      end

      # The address of a stack slot, materialized once per function.
      def stack_addr(slot)
        hoisted([:stack_addr, slot]) { "stack_addr.i64 #{slot}" }
      end

      def to_s
        raise "#{@current.name} of #{@name} has no terminator" unless @current.terminated?

        ClifText.render(self)
      end

      private

      def reset(name, params, ret)
        @name = name
        @params = params
        @ret = ret
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
        @args = []
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
