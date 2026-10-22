# frozen_string_literal: true

module Zr
  module Backend
    module Aarch64
      class Codegen
        # The arm64 parts of the layout: the hooks of `Native::Planner`,
        # store pairs and the pinned gate reads.

        private

        #: (IR::op op) -> bool
        def flag_neutral?(op) = FLAG_NEUTRAL.include?(op)

        #: (Integer mask, Integer bits) -> bool
        def logical_immediate?(mask, bits) = !Assembler.bitmask(mask, bits).nil?

        #: (Integer off, Integer width) -> bool
        def immediate?(off, width) = off >= 0 && (off % width).zero? && off / width <= 4095

        # One `add` from sp takes 12 bits.
        #: (Integer off) -> bool
        def slot_address?(off) = off <= 4095

        # Two `add`s from sp take 24 bits, and neither subtracts
        # (`frame_address`).
        #: (Integer off) -> bool
        def frame_reach?(off) = off.between?(0, (1 << 24) - 1)

        #: () -> Integer
        def frame_base = PAIR

        # The function must restore each callee-saved register that it
        # uses, so the frame has a place for each one. A function that
        # foreign code enters saves all of them, x28 too: then the values
        # that C keeps in them are in this frame, where the collector's
        # scan of the C frames reads them (`zr_mark_task`).
        #: (Array[Registers::Register] used) -> Array[Registers::Register]
        def callee_saves(used)
          saved = used.select { |r| POOLS.callee?(r) }
          saved = (saved + POOLS.callee + [GATES]).uniq if @enters
          saved.sort_by(&:to_i) #: Array[Registers::Register]
        end

        # Two word stores to the same base, the second 8 bytes after the
        # first, with no emitted instruction between them, become one `stp`.
        # The nil fills after every send and in every prologue are runs of
        # these. `@pairs` maps the first store to the second. `@paired`
        # contains the second stores, which emit nothing.
        #: () -> void
        def plan_pairs
          @pairs = {}
          @paired = Set.new
          @f.blocks.each do |b|
            b.insts.reject { |i| @silent.include?(i.results[0]) }.each_cons(2) do |first, second|
              next unless first && second && first.op == :store && second.op == :store && !@paired.include?(first)
              next unless first.args[1] == second.args[1] && second.offset == first.offset + 8
              next unless wide?(first.args[0]) && wide?(second.args[0])

              @pairs[first] = second
              @paired << second
            end
          end
        end

        # A `gates` value is the gate word at the time of the read. A later
        # instruction that uses the value must see that word, not the current
        # contents of the register. When every read is in the defining block
        # and before anything that can change the register (a call, because a
        # callee can set a gate, or a write to the register), each read uses
        # `x28` directly (`@pinned`). It then has no register, no home, and no
        # code at its definition, and a bit test of it is one `tbz` of `x28`.
        # Any other `gates` value is copied from the register at its definition.
        #: () -> void
        def plan_pinned
          @pinned = Set.new
          @f.blocks.each do |b|
            open = {} #: Hash[String, Integer]
            b.insts.each do |i|
              i.args.each { |a| open[a] += 1 if open.key?(a) }
              i.targets&.each { |(_, args)| args.each { |a| open[a] += 1 if open.key?(a) } }
              case i.op
              when :gates then open[i.results[0]] = 0
              when :call, :call_indirect, :gates_set, :gates_enter
                open.each { |v, n| @pinned << v if n == @uses[v] }
                open.clear
              end
            end
            open.each { |v, n| @pinned << v if n == @uses[v] }
          end
        end

        # The bytes of the x29 pair at the bottom of the frame.
        PAIR = 16
        # The largest frame that one pre-indexed `stp` makes and one
        # post-indexed `ldp` removes. Seven signed bits in units of 8 reach
        # 504, and a frame is a multiple of 16.
        SMALL = 496

        #: () -> bool
        def small_frame? = @frame <= SMALL
      end
    end
  end
end
