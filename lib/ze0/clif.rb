# frozen_string_literal: true

module Ze0
  # A CLIF function under construction: its stack slots, the symbols and
  # callees it names, and its blocks in layout order. Instructions are
  # appended as text; values and blocks are numbered here so the text is
  # in SSA form by construction.
  module Clif
    class Function
      # `current` is the block being emitted into: what a caller needs when
      # it fills a block out of order and then resumes.
      attr_reader :name, :args, :current

      # `params`/`ret`: CLIF types. The entry block takes the parameters
      # as v0..vN-1.
      def initialize(name, params, ret)
        @name = name
        @params = params
        @ret = ret
        @slots = []
        @symbols = {}
        @sigs = {}
        @callees = {}
        @blocks = []
        @labels = {}
        @body = {}
        @lines = {}
        @hoisted = {}
        @next_value = 0
        @current = nil
        @terminated = false
        @args = params.map { value }
        @entry = block_named(@args.zip(params).map { |v, t| "#{v}: #{t}" })
        switch(@entry)
      end

      # A fresh stack slot of `bytes`.
      def slot(bytes = Capi::SLOT_BYTES)
        @slots << "explicit_slot #{bytes}, align = 8"
        "ss#{@slots.size - 1}"
      end

      # The global value naming `symbol`.
      def symbol(symbol, colocated: true)
        @symbols[symbol] ||= begin
          gv = "gv#{@symbols.size}"
          @lines[gv] = "#{gv} = symbol #{colocated ? "colocated " : ""}%#{symbol}"
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
        @callees[symbol] ||= begin
          sig = signature(params, ret)
          fn = "fn#{@callees.size}"
          @lines[fn] = "#{fn} = #{colocated ? "colocated " : ""}%#{symbol} #{sig}"
          fn
        end
      end

      # A new block; `params` are CLIF types, and the block's parameter
      # values are answered beside its name.
      def block(params = [])
        values = params.map { value }
        name = block_named(values.zip(params).map { |v, t| "#{v}: #{t}" })
        [name, values]
      end

      # A block taking no parameters, by name alone.
      def label
        block.first
      end

      # Continue emitting into `block`. The block being left must have
      # ended in a jump, a branch or a return.
      def switch(block)
        raise "#{@current} of #{@name} was left without a terminator" if @current && !@terminated

        @current = block
        @terminated = false
        @blocks << block
      end

      # Whether the current block has already ended.
      def terminated?
        @terminated
      end

      # An instruction with no result.
      def ins(text)
        raise "an instruction after the terminator of #{@current} in #{@name}" if @terminated

        (@body[@current] ||= []) << text
        @terminated = true if terminator?(text)
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

      # The address of a stack slot, materialized once per function.
      def stack_addr(slot)
        hoisted([:stack_addr, slot]) { "stack_addr.i64 #{slot}" }
      end

      def to_s
        raise "#{@current} of #{@name} has no terminator" unless @terminated

        out = +"function %#{@name}(#{@params.join(", ")})"
        out << " -> #{@ret}" if @ret
        out << " system_v {\n"
        @slots.each_with_index { |s, i| out << "    ss#{i} = #{s}\n" }
        @symbols.each_value { |gv| out << "    #{@lines[gv]}\n" }
        @sigs.each_value { |sig| out << "    #{@lines[sig]}\n" }
        @callees.each_value { |fn| out << "    #{@lines[fn]}\n" }
        @blocks.each do |b|
          out << "\n#{@labels[b]}:\n"
          (@body[b] || []).each { |line| out << "    #{line}\n" }
        end
        out << "}\n"
      end

      private

      def value
        v = "v#{@next_value}"
        @next_value += 1
        v
      end

      def block_named(params)
        name = "block#{@labels.size}"
        @labels[name] = params.empty? ? name : "#{name}(#{params.join(", ")})"
        name
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
          body = (@body[@entry] ||= [])
          at = body.size
          at -= 1 if at.positive? && terminator?(body.last)
          body.insert(at, "#{v} = #{yield}")
          v
        end
      end

      def terminator?(text)
        text.start_with?("jump ", "brif ", "return")
      end

      def signature(params, ret)
        key = [params, ret]
        @sigs[key] ||= begin
          sig = "sig#{@sigs.size}"
          text = "(#{params.join(", ")})"
          text += " -> #{ret}" if ret
          @lines[sig] = "#{sig} = #{text} system_v"
          sig
        end
      end
    end
  end
end
