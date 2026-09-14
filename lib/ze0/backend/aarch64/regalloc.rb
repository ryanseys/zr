# frozen_string_literal: true

require "set"

require_relative "registers"

module Ze0
  module Backend
    module Aarch64
      # Which values live in a register for the whole of their life, and
      # which stay in the frame.
      #
      # Linear scan over intervals in block layout order. Every value
      # keeps the frame home the backend already gives it, so a value this
      # answers nothing for behaves exactly as it did before: the
      # allocator can be conservative without ever being wrong, and when
      # it runs out of registers it spills by leaving a value where it
      # already was.
      #
      # It hands out `x19`..`x28` and nothing else. They are callee-saved,
      # so a value in one survives a call with no work at the call site,
      # and none of them is scratch for a lowering. `x18` is reserved on
      # this platform and is never touched.
      #
      # Every value, block and instruction is given a number first, and
      # what follows indexes arrays by those numbers. This is most of what
      # the backend spends -- compiling the compiler is twenty seconds of
      # backend against four of everything before it -- and a String key
      # costs a hash of its bytes at every single use.
      class Regalloc
        include Registers

        POOL = [X19, X20, X21, X22, X23, X24, X25, X26, X27, X28].freeze
        # A value is the only entity the builder names with a leading
        # `v`: a block is `block0`, a global `gv0`, a slot `ss0`, a callee
        # `fn0` and a signature `sig0`. Testing the first byte is worth
        # doing rather than matching a pattern, because this runs once per
        # operand of every instruction in the program.
        def self.value?(name) = name.is_a?(String) && name.start_with?("v")

        # `{ "v3" => X19, ... }` for the values worth a register. `skip`
        # names values the backend makes where they are read instead, so
        # they need no register and must not keep one from anything else.
        def self.of(function, skip: nil) = new(function, skip).assign

        def initialize(function, skip = nil)
          @f = function
          @skip = skip
        end

        def assign
          # A block emitted twice would give one name two places in the
          # numbering, and every interval below would be nonsense. The
          # builder does not do it; if it ever does, spill everything.
          return {} if @f.blocks.map(&:name).uniq.size != @f.blocks.size

          number
          flow
          named(scan(*intervals))
        end

        private

        # A number for every block, every instruction and every value.
        # `@uses` and `@results` hold value numbers at an instruction's
        # own number, so nothing below hashes a name or an object again.
        def number
          @order = {}
          @f.blocks.each_with_index { |b, i| @order[b.name] = i }
          # A Hash that numbers what it is asked for is one lookup where
          # `@id[name] ||= @id.size` is two.
          @id = Hash.new { |h, name| h[name] = h.size }
          @first = []
          @last = []
          @uses = []
          @results = []
          @params = []
          at = 0
          @f.blocks.each_with_index do |b, bi|
            @first[bi] = at
            @params[bi] = b.params.map { |v, _| @id[v] }
            b.insts.each do |i|
              @uses[at] = operands(i)
              @results[at] = i.results.map { |v| @id[v] }
              at += 1
            end
            @last[bi] = at - 1
          end
          @points = at
        end

        # The values an instruction reads, by number: its own operands,
        # and the arguments it carries to a block it branches to.
        def operands(inst)
          used = []
          inst.args.each { |a| used << @id[a] if Regalloc.value?(a) }
          inst.targets&.each { |(_, args)| args.each { |a| used << @id[a] if Regalloc.value?(a) } }
          used
        end

        # Live-in and live-out per block, to a fixed point. A block
        # parameter is defined at its own block's entry, so it is never
        # live in there; the arguments a jump carries are uses in the
        # block that jumps.
        #
        # Only a block whose successor has changed can change, so the work
        # is a list rather than a sweep over every block until nothing
        # moves: a long chain of blocks settles in one pass instead of one
        # pass a block.
        def flow
          count = @f.blocks.size
          gen = Array.new(count) { |bi| upward(bi) }
          kill = Array.new(count) { |bi| killed(bi) }
          into = Array.new(count) { Set.new }
          before = predecessors
          # Popped from the end, so the last block settles first: liveness
          # flows backwards, and a chain then settles in one pass.
          work = (0...count).to_a
          queued = Array.new(count, true)
          until work.empty?
            bi = work.pop
            queued[bi] = false
            out = union(into, successors[bi])
            now = out.subtract(kill[bi]).merge(gen[bi])
            next if now == into[bi]

            into[bi] = now
            before[bi].each do |p|
              next if queued[p]

              queued[p] = true
              work << p
            end
          end
          @live_in = into
          @live_out = Array.new(count) { |bi| union(into, successors[bi]) }
        end

        # What is live into all of `blocks`, as a Set of its own. Almost
        # every block runs into exactly one other, and a copy of that
        # block's own answer is cheaper than merging into an empty Set.
        def union(into, blocks)
          case blocks.size
          when 0 then Set.new
          when 1 then into[blocks[0]].dup
          else
            all = into[blocks[0]].dup
            1.upto(blocks.size - 1) { |i| all.merge(into[blocks[i]]) }
            all
          end
        end

        def predecessors
          before = Array.new(@f.blocks.size) { [] }
          successors.each_with_index { |ss, bi| ss.each { |s| before[s] << bi } }
          before
        end

        def successors
          @successors ||= @f.blocks.map do |b|
            (b.insts.last&.targets || []).map { |t| @order.fetch(t.first) }
          end
        end

        # The values a block reads before it writes them.
        # A value at a time rather than `merge` and `subtract` of the
        # arrays: an instruction names one or two, and the call costs
        # more than the work.
        def upward(bi)
          live = Set.new
          @last[bi].downto(@first[bi]) do |point|
            @results[point].each { |v| live.delete(v) }
            @uses[point].each { |v| live.add(v) }
          end
          @params[bi].each { |v| live.delete(v) }
          live
        end

        def killed(bi)
          live = Set.new(@params[bi])
          @first[bi].upto(@last[bi]) { |point| @results[point].each { |v| live.add(v) } }
          live
        end

        # One interval a value, covering every point it can be read at:
        # where it is defined, where it is used, and the whole of any
        # block it is live across. Covering the holes as well is
        # conservative, and conservative here means correct.
        #
        # `[order, from, to]`: the values that have an interval, in scan
        # order, and where each one begins and ends. Three arrays and not
        # a list of triples, because a triple a value was a fifth of
        # everything the backend allocated.
        def intervals
          count = @id.size
          from = Array.new(count)
          to = Array.new(count)
          @f.blocks.each_with_index do |b, bi|
            first = @first[bi]
            last = @last[bi]
            @params[bi].each { |v| reach(from, to, v, first) }
            first.upto(last) do |point|
              @results[point].each { |v| reach(from, to, v, point) }
              @uses[point].each { |v| reach(from, to, v, point) }
            end
            @live_in[bi].each { |v| reach(from, to, v, first) }
            @live_out[bi].each { |v| reach(from, to, v, last) }
          end
          # By start, then by end, then by the value's own number. Ruby's
          # sort is not a stable one, so without that last term which of
          # two intervals that begin and end together keeps a register
          # would be the sort's own business. Naming the value settles it
          # outright, and owes nothing to the order anything above was
          # walked in. One Integer carries all three.
          span = @points + 1
          @skip&.each { |name| from[@id[name]] = nil if @id.key?(name) }
          order = (0...count).select { |v| from[v] }
          order.sort_by! { |v| (((from[v] * span) + to[v]) * count) + v }
          [order, from, to]
        end

        # `v` reaches `point`, so its interval holds it.
        def reach(from, to, v, point)
          low = from[v]
          if low.nil?
            from[v] = point
            to[v] = point
            return
          end
          from[v] = point if point < low
          to[v] = point if point > to[v]
        end

        # Linear scan: hand a register to each interval in start order,
        # giving back the ones whose values are dead. When the pool is
        # empty the longest-lived interval loses its register, because it
        # is the one that would hold a register longest for the least.
        #
        # The lowest free register goes first. The frame saves and restores
        # every register a function uses, so a function whose values live
        # a line each should touch two registers, not cycle through all
        # ten: for a three-line predicate that was twenty of its sixty-two
        # instructions.
        def scan(order, from, to)
          free = POOL.dup
          active = []
          taken = {}
          order.each do |value|
            first = from[value]
            active.reject! do |other|
              next false if to[other] >= first

              release(free, taken.fetch(other))
              true
            end
            if free.empty?
              longest = active.max_by { |other| to[other] }
              next if longest.nil? || to[value] > to[longest]

              release(free, taken.delete(longest))
              active.delete(longest)
            end
            taken[value] = free.shift
            active << value
          end
          taken
        end

        # `reg` back in `free`, which stays in pool order.
        def release(free, reg)
          at = free.index { |other| other.to_i > reg.to_i } || free.size
          free.insert(at, reg)
        end

        # The backend asks by name, so the numbers go back to names here
        # and nowhere else.
        def named(taken)
          return {} if taken.empty?

          names = @id.keys
          taken.to_h { |v, reg| [names[v], reg] }
        end
      end
    end
  end
end
