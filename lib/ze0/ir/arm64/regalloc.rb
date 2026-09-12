# frozen_string_literal: true

require "set"

require_relative "../../machine/aarch64"

module Ze0
  module IR
    class Arm64
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
      class Regalloc
        include Machine::Aarch64::Registers

        POOL = [X19, X20, X21, X22, X23, X24, X25, X26, X27, X28].freeze
        # A value is the only entity the builder names with a leading
        # `v`: a block is `block0`, a global `gv0`, a slot `ss0`, a callee
        # `fn0` and a signature `sig0`. Testing the first byte is worth
        # doing rather than matching a pattern, because this runs once per
        # operand of every instruction in the program.
        def self.value?(name) = name.is_a?(String) && name.start_with?("v")

        # `{ "v3" => X19, ... }` for the values worth a register.
        def self.of(function) = new(function).assign

        def initialize(function)
          @f = function
        end

        def assign
          # A block emitted twice would give one name two places in the
          # numbering, and every interval below would be nonsense. The
          # builder does not do it; if it ever does, spill everything.
          return {} if @f.blocks.map(&:name).uniq.size != @f.blocks.size

          number
          flow
          scan(intervals)
        end

        private

        # Each block's span in one numbering over the whole function, in
        # the order the backend lays the blocks out.
        def number
          at = 0
          @first = {}
          @last = {}
          @at = {}
          @uses = {}
          @f.blocks.each do |b|
            @first[b.name] = at
            b.insts.each do |i|
              @at[i] = at
              @uses[i] = operands(i)
              at += 1
            end
            @last[b.name] = at - 1
          end
        end

        # The values an instruction reads: its own operands, and the
        # arguments it carries to a block it branches to.
        def operands(inst)
          used = inst.args.select { |a| Regalloc.value?(a) }
          inst.targets&.each { |(_, args)| used.concat(args.select { |a| Regalloc.value?(a) }) }
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
          gen = @f.blocks.to_h { |b| [b.name, upward(b)] }
          kill = @f.blocks.to_h { |b| [b.name, defined(b)] }
          into = @f.blocks.to_h { |b| [b.name, Set.new] }
          before = predecessors
          # Popped from the end, so the last block settles first: liveness
          # flows backwards, and a chain then settles in one pass.
          work = @f.blocks.map(&:name)
          queued = work.to_set
          until work.empty?
            name = work.pop
            queued.delete(name)
            out = successors_of(name).inject(Set.new) { |all, s| all | into.fetch(s) }
            now = gen.fetch(name) | (out - kill.fetch(name))
            next if now == into.fetch(name)

            into[name] = now
            before.fetch(name).each { |p| work << p if queued.add?(p) }
          end
          @live_in = into
          @live_out = @f.blocks.to_h do |b|
            [b.name, successors_of(b.name).inject(Set.new) { |all, s| all | into.fetch(s) }]
          end
        end

        def predecessors
          before = @f.blocks.to_h { |b| [b.name, []] }
          @f.blocks.each { |b| successors_of(b.name).each { |s| before.fetch(s) << b.name } }
          before
        end

        def successors_of(name)
          @successors ||= @f.blocks.to_h { |b| [b.name, (b.insts.last&.targets || []).map(&:first)] }
          @successors.fetch(name)
        end

        # The values a block reads before it writes them.
        def upward(block)
          live = Set.new
          block.insts.reverse_each do |i|
            live.subtract(i.results)
            live.merge(@uses.fetch(i))
          end
          live.subtract(block.params.map(&:first))
          live
        end

        def defined(block)
          block.params.map(&:first).to_set.merge(block.insts.flat_map(&:results))
        end

        # One interval a value, covering every point it can be read at:
        # where it is defined, where it is used, and the whole of any
        # block it is live across. Covering the holes as well is
        # conservative, and conservative here means correct.
        def intervals
          span = {}
          @f.blocks.each do |b|
            first = @first[b.name]
            last = @last[b.name]
            b.params.each { |v, _| reach(span, v, first) }
            b.insts.each do |i|
              point = @at[i]
              i.results.each { |v| reach(span, v, point) }
              @uses.fetch(i).each { |v| reach(span, v, point) }
            end
            @live_in[b.name].each { |v| reach(span, v, first) }
            @live_out[b.name].each { |v| reach(span, v, last) }
          end
          span.map { |v, (from, to)| [v, from, to] }.sort_by { |_, from, to| [from, to] }
        end

        # `v` reaches `point`, so its interval holds it.
        def reach(span, v, point)
          at = span[v]
          return span[v] = [point, point] unless at

          at[0] = point if point < at[0]
          at[1] = point if point > at[1]
        end

        # Linear scan: hand a register to each interval in start order,
        # giving back the ones whose values are dead. When the pool is
        # empty the longest-lived interval loses its register, because it
        # is the one that would hold a register longest for the least.
        def scan(intervals)
          free = POOL.dup
          active = []
          taken = {}
          intervals.each do |(value, first, last)|
            active.reject! do |other|
              next false if other[2] >= first

              free << taken.fetch(other[0])
              true
            end
            if free.empty?
              longest = (active + [[value, first, last]]).max_by { |iv| iv[2] }
              next if longest[0] == value

              free << taken.delete(longest[0])
              active.delete(longest)
            end
            taken[value] = free.shift
            active << [value, first, last]
          end
          taken
        end
      end
    end
  end
end
