# frozen_string_literal: true

module Ze0
  module Backend
    module Wasm
      # Which wasm local each value of a function is kept in: values whose
      # lives never overlap share one, if their wasm types agree.
      #
      # A local for every value is what a wasm compiler pays for. Cranelift
      # makes each local a variable and builds SSA for it again, through
      # the one loop every block is dispatched from, and its memory grows
      # faster than the count: a function of 11,420 locals took 617 MB to
      # compile, and 165 MB once they were shared down to 718.
      #
      # Liveness is found from the uses: a value read in a block other than
      # the one defining it is live into that block, and out of each
      # predecessor, and so on back to its definition. Most values are
      # read only where they are made and cost nothing here. Colouring
      # then walks the blocks in reverse postorder, so a value's
      # definition, which dominates its uses, comes before them, and every
      # value live where another is defined already has its local. That is
      # enough for greedy colouring to be right: of two values live at once,
      # one is live where the other is defined.
      #
      # Two writes need more than liveness. A jump writes all of a block's
      # parameters, a dead one too, so the parameters hold distinct locals.
      # And an instruction's results never take the local of one of its own
      # arguments: the overflow instructions read their arguments again
      # after writing the first result.
      class Locals
        # `{ value => local index }` over `values`, `[value, wasm type]`
        # pairs, and the wasm type of each local from `base` on, where the
        # shared locals begin.
        def self.of(f, values, base) = new(f, values, base).assign

        def initialize(f, values, base)
          @f = f
          @values = values
          @base = base
        end

        def assign
          number
          live
          colour
          [@local, @types]
        end

        private

        # A number for each value, the block defining it, each block's
        # successors and predecessors, and the index of the instruction
        # that last reads each value in its block.
        def number
          @id = {}
          @wasm = []
          @values.each do |v, t|
            @id[v] = @wasm.size
            @wasm << t
          end
          blocks = @f.blocks
          index = {}
          blocks.each_with_index { |b, bi| index[b.name] = bi }
          @home = Array.new(@wasm.size)
          @succ = []
          @pred = Array.new(blocks.size) { [] }
          @last = []
          @uses = []
          blocks.each_with_index do |b, bi|
            b.params.each { |v, _| (n = @id[v]) && @home[n] = bi }
            last = {}
            id = @id
            b.insts.each_with_index do |i, k|
              # Only a value has a number: an immediate or an entity name
              # finds none.
              i.args.each { |a| (n = id[a]) && last[n] = k }
              i.targets&.each { |(_, args)| args.each { |a| (n = id[a]) && last[n] = k } }
              i.results.each { |v| (n = id[v]) && @home[n] = bi }
            end
            @last << last
            @uses << last.keys
            succ = (b.insts.last&.targets || []).map { |name, _| index.fetch(name) }
            @succ << succ
            succ.each { |s| @pred[s] << bi }
          end
        end

        # `@in[block]`, the values live into it, and `@out[block]`, those
        # live out of it as a Hash, walking back from each use.
        def live
          n = @f.blocks.size
          @in = Array.new(n) { [] }
          @out = Array.new(n) { {} }
          seen = Array.new(n)
          @uses.each_with_index do |used, bi|
            used.each do |v|
              home = @home[v]
              next if home == bi || home.nil? || seen[bi] == v

              seen[bi] = v
              @in[bi] << v
              work = [bi]
              until work.empty?
                @pred[work.pop].each do |p|
                  @out[p][v] = true
                  next if p == home || seen[p] == v

                  seen[p] = v
                  @in[p] << v
                  work << p
                end
              end
            end
          end
        end

        # Postorder of the blocks reached from the entry; `@reached` is
        # how many, and the ones nothing reaches follow.
        def postorder
          seen = Array.new(@f.blocks.size, false)
          order = []
          stack = [[0, 0]]
          seen[0] = true
          until stack.empty?
            frame = stack.last
            bi, k = frame
            if k < @succ[bi].size
              frame[1] += 1
              s = @succ[bi][k]
              next if seen[s]

              seen[s] = true
              stack << [s, 0]
            else
              order << bi
              stack.pop
            end
          end
          @reached = order.size
          order + seen.each_index.reject { |bi| seen[bi] }
        end

        def colour
          order = postorder
          @colour = Array.new(@wasm.size)
          @types = []
          # Per type: the locals of that type, those given back in the block
          # being coloured, and how far into the first a search has gone.
          # `@busy[local]` is the block whose walk holds it, so nothing is
          # cleared between blocks.
          @of_type = Hash.new { |h, t| h[t] = [] }
          @freed = Hash.new { |h, t| h[t] = [] }
          @cursor = Hash.new(0)
          @busy = []
          @stamp = 0
          # The reached blocks in reverse postorder, then the rest.
          order.first(@reached).reverse_each { |bi| colour_block(bi) }
          order.drop(@reached).each { |bi| colour_block(bi) }
          @local = {}
          @values.each { |v, _| @local[v] = @base + @colour[@id[v]] }
        end

        # A block's values their locals. A local is free when no value
        # live at this point holds it: those given back in this block wait
        # on a stack, and the rest are found by a cursor over each type's
        # locals, so a block costs what is live in it and not every local
        # the function has.
        def colour_block(bi)
          b = @f.blocks[bi]
          @stamp += 1
          @freed.each_value(&:clear)
          @cursor.clear
          stamp = @stamp
          busy = @busy
          colour = @colour
          @in[bi].each do |n|
            c = colour[n]
            busy[c] = stamp if c
          end
          out = @out[bi]
          last = @last[bi]
          id = @id
          unless b.params.empty?
            # A jump writes every parameter, a dead one too, so they all
            # hold a local of their own until the last is written.
            params = b.params.filter_map { |v, _| id[v] }
            params.each { |n| take(n) }
            params.each { |n| release(n) unless last.key?(n) || out.key?(n) }
          end
          b.insts.each_with_index do |i, k|
            results = i.results
            results.each { |v| (n = id[v]) && take(n) }
            i.args.each { |a| (n = id[a]) && last[n] == k && free_read(n, last, out) }
            i.targets&.each { |(_, args)| args.each { |a| (n = id[a]) && last[n] == k && free_read(n, last, out) } }
            results.each do |v|
              n = id[v]
              release(n) if n && !last.key?(n) && !out.key?(n)
            end
          end
        end

        # A value read for the last time in its block, and not live out of
        # it, gives its local back; once, however many times it is read.
        def free_read(n, last, out)
          return if out.key?(n)

          last.delete(n)
          release(n)
        end

        def take(n)
          t = @wasm[n]
          c = @freed[t].pop
          unless c
            all = @of_type[t]
            at = @cursor[t]
            busy = @busy
            stamp = @stamp
            at += 1 while at < all.size && busy[all[at]] == stamp
            if at < all.size
              c = all[at]
              @cursor[t] = at + 1
            else
              c = @types.size
              @types << t
              all << c
              @cursor[t] = all.size
            end
          end
          @busy[c] = @stamp
          @colour[n] = c
        end

        def release(n)
          c = @colour[n] or return
          @busy[c] = nil
          @freed[@wasm[n]] << c
        end
      end
    end
  end
end
