# frozen_string_literal: true

require_relative "registers"

module Zr
  module Backend
    module Aarch64
      # Selects the values that stay in a register for all of their life.
      # The other values stay in the frame.
      #
      # Linear scan over intervals in block layout order. Every value keeps
      # its frame home from the backend. A value that gets no register uses
      # that home, so the allocator can be conservative and still correct.
      # When it has no free register, it spills a value by leaving it in its home.
      #
      # Two pools. A value live across a call gets one of the callee-saved
      # `x19`..`x27`. The frame saves and restores each one that the function
      # uses. A value that crosses no call gets one of `CALLER` first, which
      # nothing saves: most values in a kernel function live between two
      # calls, and a callee-saved register for each costs the saves of all
      # ten. It gets a callee-saved register only when `CALLER` is empty. A
      # crossing value never gets a caller-saved register.
      #
      # The argument registers `x0`..`x7` are in `CALLER`. A call clobbers
      # them, but a value that crosses no call is dead at that point. Arguments
      # and parameters move as one parallel copy (`Codegen#load_args`,
      # `#prologue`), so a value can use an argument register. Reserved:
      # `x9`..`x12` (lowering scratch), `x16` and `x17` (linker), `x18`
      # (platform), and `x28` (the program's gate word, `GATES`; a `gates`
      # value reads it and gets no register).
      #
      # Every value, block and instruction gets a number first, and the
      # code indexes arrays by these numbers. Allocation is most of the
      # backend time (20 seconds of backend against 4 for all earlier steps
      # when compiling the compiler), and a String key hashes its bytes at each use.
      class Regalloc
        include Registers

        CALLEE = [X19, X20, X21, X22, X23, X24, X25, X26, X27].freeze
        GATES = X28
        CALLER = [X0, X1, X2, X3, X4, X5, X6, X7, X8, X13, X14, X15].freeze

        # Whether `reg` is one the callee saves.
        def self.callee?(reg) = reg.to_i >= 19
        def self.value?(name) = IR.value?(name)

        # Returns `{ "v3" => X19, ... }` for the values that get a register.
        # `skip` gives the values that the backend makes at each read. They
        # need no register and must not block one. `via` maps a value that
        # the backend reads through another value to that other value, which
        # is then live at every read of the first.
        def self.of(function, skip: nil, via: nil) = new(function, skip, via).assign

        def initialize(function, skip = nil, via = nil)
          @f = function
          @skip = skip
          @via = via
        end

        def assign
          # A block emitted two times gives one name two positions in the
          # numbering, and every interval is then wrong. The builder does
          # not do this. If it does, spill all values.
          return {} if @f.blocks.map(&:name).uniq.size != @f.blocks.size

          number
          named(scan(*intervals))
        end

        # The instructions that call. At these, a value loses its register
        # unless the callee saves it.
        CALLS = %i[call call_indirect].freeze
        NOTHING = [].freeze

        private

        # A number for every block, every instruction and every value.
        # `@uses` and `@results` contain value numbers at the index of the
        # instruction, so the code below does not hash a name or an object again.
        #
        # A block's first point is its entry, where its parameters arrive and
        # its live-in values are live. Its instructions start at the next
        # point. Thus a call at the first instruction is strictly after both,
        # as `crosses_call?` requires.
        #
        # A value in `skip` gets no number: it has no interval, so it must not
        # add liveness work. The other values keep their order, so the tie
        # breaks in `intervals` do not change.
        def number
          @order = {}
          @f.blocks.each_with_index { |b, i| @order[b.name] = i }
          # A Hash that numbers each new key does one lookup.
          # `@id[name] ||= @id.size` does two.
          @id = Hash.new { |h, name| h[name] = h.size }
          @first = []
          @last = []
          @uses = []
          @results = []
          @params = []
          @defined_in = []
          @calls = []
          at = 0
          @f.blocks.each_with_index do |b, bi|
            @first[bi] = at
            @params[bi] = b.params.filter_map { |v, _| numbered(v) }
            @params[bi].each { |v| @defined_in[v] = bi }
            @uses[at] = @results[at] = NOTHING
            at += 1
            b.insts.each do |i|
              @uses[at] = operands(i)
              @results[at] = i.results.filter_map { |v| numbered(v) }
              @results[at].each { |v| @defined_in[v] = bi }
              @calls << at if CALLS.include?(i.op)
              at += 1
            end
            @last[bi] = at - 1
          end
          @points = at
        end

        # Returns the number of `name`, or nil when the backend makes it at its reads.
        def numbered(name) = (@id[name] unless @skip&.include?(name))

        # The values that an instruction reads, by number: its operands, and
        # the arguments that it gives to a branch target block.
        def operands(inst)
          used = []
          inst.args.each { |a| (v = read(a)) && used << v }
          inst.targets&.each { |(_, args)| args.each { |a| (v = read(a)) && used << v } }
          used
        end

        # Returns the number of the value that a read of `a` keeps live, or
        # nil when `a` is not a value or is made at its reads.
        def read(a)
          return nil unless Regalloc.value?(a)

          a = @via[a] || a if @via
          numbered(a)
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

        # One interval for each value. It covers every point where the value
        # can be read: its definition, its uses, and all of each block that
        # it is live across. The interval also covers the holes. This is
        # conservative, and thus correct.
        #
        # Returns `[order, from, to, crossing]`: the values that have an
        # interval in scan order, the start and end of each, and whether a
        # call is strictly inside it. These are parallel Arrays, not tuples,
        # because one tuple for each value is a fifth of all backend allocations.
        def intervals
          count = @id.size
          from = Array.new(count)
          to = Array.new(count)
          # For each value, the blocks other than its defining block that read it.
          away = Array.new(count)
          @f.blocks.each_index do |bi|
            first = @first[bi]
            @params[bi].each { |v| reach(from, to, v, first) }
            first.upto(@last[bi]) do |point|
              @results[point].each { |v| reach(from, to, v, point) }
              @uses[point].each do |v|
                reach(from, to, v, point)
                (away[v] ||= []) << bi unless @defined_in[v] == bi
              end
            end
          end
          live = Array.new(@f.blocks.size)
          before = predecessors
          # A value that the entry block makes (every constant is one) is
          # live through every block that flows into a block that reads it.
          # Its interval ends at the latest of those blocks. One pass over the
          # blocks finds this for all such values, in place of one walk for
          # each value (blocks times constants).
          entry = @order.fetch(@f.entry_block.name)
          latest = before[entry].empty? && away.any? && latest_before(before, entry)
          away.each_with_index do |blocks, v|
            next unless blocks

            if latest && @defined_in[v] == entry
              blocks.each { |bi| reach(from, to, v, latest[bi]) }
            else
              blocks.each { |bi| live_into(bi, v, from, to, live, before) }
            end
          end
          # Sort by start, then by end, then by the value's number. Ruby's
          # sort is not stable. Without the last key, the sort alone selects
          # which of two intervals with the same start and end gets a register.
          # The value number makes the order fixed. One Integer contains all three keys.
          span = @points + 1
          order = (0...count).select { |v| from[v] }
          order.sort_by! { |v| (((from[v] * span) + to[v]) * count) + v }
          crossing = order.to_h { |v| [v, crosses_call?(from[v], to[v])] }
          refine_crossing(crossing, from, to, away, before)
          [order, from, to, crossing]
        end

        # Whether a call is strictly between `from` and `to`. A value that a
        # call makes starts at the call, and a value that a call reads last
        # ends at the call. Neither value must survive the call.
        def crosses_call?(from, to)
          i = @calls.bsearch_index { |c| c > from }
          !i.nil? && @calls[i] < to
        end

        # An interval covers its holes, so the hull test above counts a call
        # in a hole as crossed. The value then gets a callee-saved register
        # that it does not need. Example: the arity check and its failure
        # call read a method's argument count, and the stack check's call is
        # between them, in a block where the count is not live.
        #
        # A value is live at a call only when some path from the call reads
        # it. Thus each crossing value is checked again against the blocks it
        # is live in. It does not cross when each call in its hull is in a
        # block where it is not live, or after its last read in a block where
        # it dies. Then nothing reads its register after the call, so a
        # caller-saved register is safe. The cost is values times blocks, so
        # a function past this bound keeps the hull test's result.
        REFINE_BOUND = 1_000_000

        def refine_crossing(crossing, from, to, away, before)
          candidates = crossing.select { |_, c| c }.keys
          return if candidates.empty? || candidates.size * @f.blocks.size > REFINE_BOUND

          # The block of each call and, for each candidate, the last point
          # of each block that reads it. One pass over the points finds both.
          call_block = @calls.map { |c| block_of(c) }
          last_read = {}
          candidates.each { |v| last_read[v] = {} }
          @f.blocks.each_index do |bi|
            @first[bi].upto(@last[bi]) do |point|
              @uses[point].each { |v| (reads = last_read[v]) && reads[bi] = point }
            end
          end
          candidates.each do |v|
            live_in = {}
            (away[v] || NOTHING).each { |bi| mark_live_in(bi, v, live_in, before) }
            crossing[v] = crossed?(v, from[v], to[v], live_in, call_block, last_read[v])
          end
        end

        # The block that contains `point`.
        def block_of(point)
          b = @first.bsearch_index { |s| s > point }
          b.nil? ? @first.size - 1 : b - 1
        end

        # Marks `{ block => true }` for every block that `v` is live into:
        # each block other than its definition that reads it, and every block
        # that flows into one of those, back to the block that makes it.
        def mark_live_in(bi, v, live_in, before)
          return if live_in[bi]

          live_in[bi] = true
          work = [bi]
          until work.empty?
            b = work.pop
            before[b].each do |p|
              next if @defined_in[v] == p || live_in[p]

              live_in[p] = true
              work << p
            end
          end
        end

        # Whether `v` is live at a call in its hull. That is a call in a
        # block where `v` is live-in or defined, before its last read there,
        # or a call in a block where `v` is live-out (live into a successor).
        def crossed?(v, from, to, live_in, call_block, last_read)
          i = @calls.bsearch_index { |c| c > from }
          return false if i.nil?

          while i < @calls.size && @calls[i] < to
            c = @calls[i]
            b = call_block[i]
            i += 1
            next unless live_in[b] || @defined_in[v] == b
            return true if successors[b].any? { |s| live_in[s] }

            last = last_read[b]
            return true if last && c < last
          end
          false
        end

        # Block `bi` reads `v`, and another block makes it. Thus `v` is live
        # into `bi`, and live out of every block that flows into a block where
        # it is live, back to its definition. Its interval covers all of those blocks.
        #
        # This works per value, not with a set of live values for each block,
        # because those sets grow as blocks times values. `live` gives the
        # value that last marked a block live-in. All reads of one value are
        # walked before the next value, so each block is walked once per
        # value. The walk uses a list, not recursion, because a chain of
        # blocks can be as long as the function.
        def live_into(bi, v, from, to, live, before)
          return if live[bi] == v

          live[bi] = v
          work = [bi]
          until work.empty?
            b = work.pop
            reach(from, to, v, @first[b])
            before[b].each do |p|
              reach(from, to, v, @last[p])
              next if @defined_in[v] == p || live[p] == v

              live[p] = v
              work << p
            end
          end
        end

        # For each block, the last point of the latest block that flows into
        # it, directly or not, excluding the entry block's predecessors. This
        # is how long a value made in the entry block and read in that block
        # stays live. A loop can increase a block's result after its successors
        # have read it, so the pass repeats until no result changes. That is
        # one more pass than the deepest nest of back edges.
        def latest_before(before, entry)
          latest = Array.new(@f.blocks.size, -1)
          moved = true
          while moved
            moved = false
            before.each_with_index do |ps, b|
              best = latest[b]
              ps.each do |p|
                best = @last[p] if @last[p] > best
                best = latest[p] if p != entry && latest[p] > best
              end
              next if best == latest[b]

              latest[b] = best
              moved = true
            end
          end
          latest
        end

        # `v` reaches `point`, so its interval must contain it.
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

        # Linear scan: give a register to each interval in start order, and
        # free the registers of dead values. When the pools for an interval
        # are empty, the longest interval that could give up a register
        # loses it, because it uses a register for the longest time.
        #
        # The lowest free register goes first. The frame saves and restores
        # every callee-saved register that a function uses. Thus a function
        # whose values each live for one line must use two registers, not all
        # ten. In a three-line predicate, the saves for ten were 20 of 62 instructions.
        def scan(order, from, to, crossing)
          free = { callee: CALLEE.dup, caller: CALLER.dup }
          active = []
          taken = {}
          arrives = arrival_registers
          order.each do |value|
            first = from[value]
            active.reject! do |other|
              next false if to[other] >= first

              release(free, taken.fetch(other))
              true
            end
            # A parameter that crosses no call keeps its arrival register
            # when that register is free, so no move is necessary.
            reg = free[:caller].delete(arrives[value]) || free[:caller].shift unless crossing[value]
            reg ||= free[:callee].shift
            if reg.nil?
              held = crossing[value] ? active.select { |other| Regalloc.callee?(taken[other]) } : active
              longest = held.max_by { |other| to[other] }
              next if longest.nil? || to[value] > to[longest]

              reg = taken.delete(longest)
              active.delete(longest)
            end
            taken[value] = reg
            active << value
          end
          taken
        end

        # Returns `{ value number => register }` for the integer parameters
        # of the entry block, from the argument register of each.
        def arrival_registers
          arrives = {}
          ints = 0
          @f.entry_block.params.each do |v, t|
            next if t == "f64"

            n = numbered(v)
            arrives[n] = Registers.x(ints) if n && ints < CALLER.size
            ints += 1
          end
          arrives
        end

        # Puts `reg` back in its pool, in pool order.
        def release(free, reg)
          pool = free[Regalloc.callee?(reg) ? :callee : :caller]
          at = pool.index { |other| other.to_i > reg.to_i } || pool.size
          pool.insert(at, reg)
        end

        # The backend looks up values by name, so this is the one place
        # where numbers change back to names.
        def named(taken)
          return {} if taken.empty?

          names = @id.keys
          taken.to_h { |v, reg| [names[v], reg] }
        end
      end
    end
  end
end
