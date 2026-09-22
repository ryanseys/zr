# frozen_string_literal: true

require_relative "effects"
require_relative "promotion"
require_relative "types"

module Ze0
  module IR
    # The kernel's guard words to SSA values, over a finished function.
    #
    # The words are `PROMOTED`, by symbol and the offset of the one word
    # promoted. Today that is no word: the gate word, the first, now
    # lives in a register of its own (`Inst::GATES`, `x28`), which costs
    # a fast/slow join nothing, where a value carried through one is a
    # block parameter the allocator mostly keeps in the frame -- a store
    # and a load an edge for the one load saved (`rake codesize`: the
    # gate word, the site stamp, the constant stamp and the task pointer
    # +12%, the gate word alone +1.4%). The pass stays for the stamps, a
    # wider caller-saved pool being what lets the set grow. The poll
    # word beside the task pointer can never be one -- the timer thread
    # writes it between any two instructions, and a load of it hoisted
    # out of a loop is a loop nothing can interrupt.
    #
    # What writes a word: a store to it in this function; a call whose
    # callee's effects (`IR::Effects`, from the kernel's description)
    # include the word's region -- a send may define a method, and the
    # collector moves a stamp when it frees a class, so most calls do;
    # a call through a pointer; and a store whose region can hold the
    # word, or that has none and goes through an address the pass cannot
    # tell -- a pointer a call answered or a field holds. A slot's
    # address and a symbol's, with a constant added, it can tell. So a
    # load reads the value of the last store or the reload after the
    # last write on the way there, or the load at entry when nothing
    # precedes it; a reload is made only when something reads it, after
    # the instruction it follows. A fast path holds no call and stores
    # only to its record slots, so a fixnum loop carries the gate word
    # in a register, and a slow path reloads and hands the join the new
    # value as a parameter. This also covers a continuation: an
    # activation it restores resumes after the call that captured it,
    # and reloads.
    #
    # A symbol's address must reach nothing but a load or a store through
    # it, plus a constant to make the address of another word beside it
    # (the poll word); passed to a call, carried to a block, stored or
    # compared, it keeps its loads. A store that covers the word in part,
    # or a load of it as another type, does the same.
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
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          insts = blocks[bi].insts
          n = 0
          while n < insts.size
            i = insts[n]
            n += 1
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
            targets = i.targets
            next unless targets

            k = 0
            while k < targets.size
              escapes(targets[k][1], refused)
              k += 1
            end
          end
          bi += 1
        end
        (loaded - refused).to_h { |symbol| [symbol, TYPE] }
      end

      # A promoted symbol whose address is among `args` is refused.
      def escapes(args, refused)
        k = 0
        while k < args.size
          a = args[k]
          refused << @addr[a][0] if @addr.key?(a)
          k += 1
        end
      end

      # `@addr`: each value that is a promoted symbol's address, or one a
      # constant past it, as `[symbol, offset]`; `@known`: every value
      # the pass can tell is not one -- a slot's or another symbol's
      # address, or a constant past either.
      def addresses
        symbol_of = @f.globals.to_h { |g| [g.gv, g.symbol] }
        @addr = {}
        @known = Set.new
        const = {}
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          insts = blocks[bi].insts
          n = 0
          while n < insts.size
            i = insts[n]
            n += 1
            case i.op
            when :iconst then const[i.results[0]] = i.args[0]
            when :stack_addr then @known << i.results[0]
            when :symbol_value
              symbol = symbol_of.fetch(i.args[0])
              PROMOTED.key?(symbol) ? @addr[i.results[0]] = [symbol, 0] : @known << i.results[0]
            end
          end
          bi += 1
        end
        return if @addr.empty?

        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          insts = blocks[bi].insts
          n = 0
          while n < insts.size
            i = insts[n]
            n += 1
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
          bi += 1
        end
      end

      # `[symbol, offset]` of the byte `addr` and `off` name in a promoted
      # symbol, or nil.
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

      # Whether it writes the whole word, as the type read.
      def defines?(symbol, at, value)
        at == PROMOTED.fetch(symbol) && type_of(value) == TYPE
      end

      # A store to a static is the kernel's alone, so the types are
      # asked for only when one turns up.
      def type_of(v) = (@types ||= Types.of(@f)).fetch(v)

      # A store to the word is a write; so is a call, or a store through
      # an address the pass cannot tell, after which every word is read
      # afresh; a load reads what the last of those left, or asks what
      # entered.
      def walk(b, keys, last, reads)
        insts = b.insts
        n = 0
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

      # The words `bits` can write are read afresh after `inst`.
      def kill(keys, last, inst, bits)
        keys.each_key { |symbol| last[symbol] = inst if Effects.writes?(bits, Effects.static_region(symbol)) }
      end

      # The word's value after the write `inst`: a reload, placed after
      # it once, when the first read asks for it.
      def after(inst, symbol)
        @reload[[inst, symbol]] ||= begin
          load = fetch(symbol)
          (@inserted[inst] ||= []) << load
          load.results[0]
        end
      end

      # The word's value where nothing wrote it: a load at the entry.
      def initial(symbol, _type)
        @initial[symbol] ||= begin
          insts = @f.entry_block.insts
          load = fetch(symbol)
          insts.insert(insts.index { |i| i.results[0] == load.args[0] } + 1, load)
          load.results[0]
        end
      end

      # A load of the word, through the address the pass itself puts at
      # the top of the entry block, which every block is dominated by.
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

      # The promoted loads go; the reloads go in after the writes they
      # follow. The stores stay, since the word is memory to every other
      # function, through the address the pass made where the function
      # had one of its own, which is then read by nothing.
      def rewrite(keys)
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          insts = blocks[bi].insts
          insts.reject! { |i| keys.key?(@loads[i]) }
          insts.replace(insts.flat_map { |i| [i, *@inserted[i]] }) if insts.any? { |i| @inserted.key?(i) }
          bi += 1
        end
        @addr.each { |v, (symbol, at)| @rename[v] = @address[symbol] if at.zero? && @address.key?(symbol) }
      end
    end
  end
end
