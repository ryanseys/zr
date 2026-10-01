# frozen_string_literal: true

require_relative "effects"
require_relative "promotion"
require_relative "types"

module Zr
  module IR
    # Promotes the kernel's guard words to SSA values in a finished
    # function. `PROMOTED` gives each word by symbol and offset.
    #
    # `PROMOTED` is empty. The gate word is in its own register
    # (`Inst::GATES`, `x28`). A promoted word becomes a block parameter
    # at each fast/slow join, and the allocator usually keeps it in the
    # frame: a store and a load for each edge, to save one load. With
    # `zr-dev codesize`, promotion of the gate word, the site stamp, the
    # constant stamp and the task pointer made code 12% larger (the gate
    # word alone, 1.4%). The pass is kept for the stamps, for when a
    # larger caller-saved register pool is available. Never promote the
    # poll word: the timer thread can write it at any time, and a load
    # hoisted out of a loop makes a loop that nothing can interrupt.
    #
    # These write a word: a store to it; a call whose `IR::Effects`
    # include its region (most calls do, because a send can define a
    # method and the collector changes a stamp when it frees a class);
    # an indirect call; a store to a region that can contain the word; a
    # store with no region through an unknown address (a pointer from a
    # call or a field). The pass knows slot and symbol addresses, plus a
    # constant. A load gets the value of the last store, or a reload
    # after the last write, or a load at entry. The pass adds a reload
    # only when something reads it. A fast path has no call and stores
    # only to its record slots, so a fixnum loop keeps the gate word in
    # a register. A slow path reloads and gives the new value to the join.
    # A restored continuation resumes after its call, so it also reloads.
    #
    # The address of a symbol can go only to a load, a store, or an add
    # of a constant (for a word next to it, such as the poll word). If
    # the address goes to a call, a block, a store, or a compare, the
    # pass does not promote the word. A store to part of the word, or a
    # load of it as a different type, also stops the promotion.
    class Statics < Promotion
      # `symbol => offset` of the word promoted.
      PROMOTED = {}.freeze

      TYPE = "i64"
      WIDTH = 8

      def initialize(f)
        super
        @effects = f.callees.to_h { |c| [c.fn, c] }
        @address = {}
        @initial = {}
        @reload = {}
        @inserted = {}.compare_by_identity
      end

      def run
        PROMOTED.empty? ? @f : super
      end

      private

      # `symbol => "i64"` of every promoted word this function loads.
      def candidates
        addresses
        return {} if @addr.empty?

        loaded = Set.new
        refused = Set.new
        @loads = {}.compare_by_identity
        @f.blocks.each do |b|
          b.insts.each do |i|
            case i.op
            when :load
              symbol, at = word(i.args[0], i.offset)
              next unless symbol && at == PROMOTED.fetch(symbol)

              if i.type == TYPE
                loaded << symbol
                @loads[i] = symbol
              else
                refused << symbol
              end
            when :store
              value, addr = i.args
              refused << @addr[value][0] if @addr.key?(value)
              symbol, at = word(addr, i.offset)
              refused << symbol if symbol && touches?(symbol, at, value) && !defines?(symbol, at, value)
            when :iadd
              escapes(i.args, refused) unless @addr.key?(i.results[0])
            else
              escapes(i.args, refused)
            end
            i.targets&.each { |_, args| escapes(args, refused) }
          end
        end
        (loaded - refused).to_h { |symbol| [symbol, TYPE] }
      end

      # If the address of a promoted symbol is in `args`, the pass does
      # not promote that symbol.
      def escapes(args, refused)
        args.each { |a| refused << @addr[a][0] if @addr.key?(a) }
      end

      # `@addr`: each value that is the address of a promoted symbol, or
      # that address plus a constant, as `[symbol, offset]`.
      # `@known`: each value that is known to be a different address (a
      # slot, another symbol, or one of these plus a constant).
      def addresses
        symbol_of = @f.globals.to_h { |g| [g.gv, g.symbol] }
        @addr = {}
        @known = Set.new
        const = {}
        @f.blocks.each do |b|
          b.insts.each do |i|
            case i.op
            when :iconst then const[i.results[0]] = i.args[0]
            when :stack_addr then @known << i.results[0]
            when :symbol_value
              symbol = symbol_of.fetch(i.args[0])
              PROMOTED.key?(symbol) ? @addr[i.results[0]] = [symbol, 0] : @known << i.results[0]
            end
          end
        end
        return if @addr.empty?

        @f.blocks.each do |b|
          b.insts.each do |i|
            next unless i.op == :iadd

            a, k = i.args
            a, k = k, a if const.key?(a)
            next unless const.key?(k)

            if @addr.key?(a)
              symbol, at = @addr[a]
              @addr[i.results[0]] = [symbol, at + const.fetch(k)]
            elsif @known.include?(a)
              @known << i.results[0]
            end
          end
        end
      end

      # Returns `[symbol, offset]` of the byte at `addr` plus `off` in a
      # promoted symbol, or nil.
      def word(addr, off)
        symbol, at = @addr[addr]
        symbol && [symbol, at + off]
      end

      # Whether a store of `value` at `at` of `symbol` covers any byte of
      # the promoted word.
      def touches?(symbol, at, value)
        first = PROMOTED.fetch(symbol)
        width = Types::WIDTH.fetch(type_of(value))
        at < first + WIDTH && first < at + width
      end

      # Whether the store writes the whole word, with the type of the load.
      def defines?(symbol, at, value)
        at == PROMOTED.fetch(symbol) && type_of(value) == TYPE
      end

      # Only the kernel stores to a static, so the pass calculates the
      # types only when it finds such a store.
      def type_of(v) = (@types ||= Types.of(@f)).fetch(v)

      # A store to the word is a write. A call, or a store through an
      # unknown address, is also a write, and each word is loaded again
      # after it. A load gets the value from the last write, or the value
      # at block entry.
      def walk(b, keys, last, reads)
        insts = b.insts
        n = 0
        # `while`: `leaving` can add a load to the head of the entry block's `insts`.
        while n < insts.size
          i = insts[n]
          n += 1
          case i.op
          when :load
            symbol = @loads[i]
            next unless symbol && keys.key?(symbol)

            if last.key?(symbol)
              @rename[i.results[0]] = leaving(b, symbol, keys)
            else
              reads << [i.results[0], b, symbol]
            end
          when :store
            addr = i.args[1]
            symbol, at = word(addr, i.offset)
            if symbol
              last[symbol] = i.args[0] if keys.key?(symbol) && at == PROMOTED.fetch(symbol)
            elsif !@known.include?(addr)
              kill(keys, last, i, i.region ? Effects.bit(i.region) : Effects::ALL)
            end
          when :call then kill(keys, last, i, @effects.fetch(i.callee).effects)
          when :call_indirect then kill(keys, last, i, Effects::ALL)
          end
        end
      end

      # After `inst`, the pass loads again each word that `bits` can write.
      def kill(keys, last, inst, bits)
        keys.each_key { |symbol| last[symbol] = inst if Effects.writes?(bits, Effects.static_region(symbol)) }
      end

      # The value of the word after the write `inst`. This is a reload
      # after `inst`, added one time, at the first read.
      def after(inst, symbol)
        @reload[[inst, symbol]] ||= begin
          load = fetch(symbol)
          (@inserted[inst] ||= []) << load
          load.results[0]
        end
      end

      # The value of the word when nothing wrote it: a load at the entry.
      def initial(symbol, _type)
        @initial[symbol] ||= begin
          insts = @f.entry_block.insts
          load = fetch(symbol)
          insts.insert(insts.index { |i| i.results[0] == load.args[0] } + 1, load)
          load.results[0]
        end
      end

      # A load of the word. The address comes from the top of the entry
      # block, which dominates all blocks.
      def fetch(symbol)
        Inst.new(:load, type: TYPE, results: [@f.value], args: [address(symbol)], offset: PROMOTED.fetch(symbol),
                 flags: "notrap aligned")
      end

      def address(symbol)
        @address[symbol] ||= begin
          v = @f.value
          @f.entry_block.insts.unshift(Inst.new(:symbol_value, type: "i64", results: [v], args: [@f.symbol(symbol)]))
          v
        end
      end

      # Deletes the promoted loads and adds each reload after its write.
      # The stores stay, because other functions read the word from
      # memory. Uses of the function's own address of the word change to
      # the address that the pass added.
      def rewrite(keys)
        @f.blocks.each do |b|
          insts = b.insts
          insts.reject! { |i| keys.key?(@loads[i]) }
          insts.replace(insts.flat_map { |i| [i, *@inserted[i]] }) if insts.any? { |i| @inserted.key?(i) }
        end
        @addr.each { |v, (symbol, at)| @rename[v] = @address[symbol] if at.zero? && @address.key?(symbol) }
      end
    end
  end
end
