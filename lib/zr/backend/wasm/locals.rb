# frozen_string_literal: true

module Zr
  module Backend
    module Wasm
      # Gives the wasm local for each value of a function. Values with the
      # same wasm type whose live ranges do not overlap share one local.
      #
      # The wasm compiler pays for each local. Cranelift builds SSA again for
      # each local through the dispatch loop, and its memory grows faster
      # than the local count: 11,420 locals took 617 MB to compile, and
      # 718 shared locals took 165 MB.
      #
      # Liveness comes from the uses: a value read in a block other than its
      # defining block is live into that block and out of each predecessor,
      # back to its definition. Colouring walks the blocks in reverse
      # postorder, so a definition comes before its uses. Of two values live
      # at the same time, one is live where the other is defined, so greedy
      # colouring is correct.
      #
      # Two rules add to liveness. A jump writes all block parameters, also
      # dead ones, so each parameter gets its own local. An instruction's
      # results never share a local with its arguments, because the overflow
      # instructions read their arguments again after they write the first result.
      class Locals
        # @rbs @f: IR::Function
        # @rbs @values: Array[[String, Integer]]
        # @rbs @base: Integer
        # @rbs @id: Hash[String, Integer]
        # @rbs @wasm: Array[Integer]
        # @rbs @home: Array[Integer?]
        # @rbs @succ: Array[Array[Integer]]
        # @rbs @pred: Array[Array[Integer]]
        # @rbs @last: Array[Hash[Integer, Integer]]
        # @rbs @uses: Array[Array[Integer]]
        # @rbs @in: Array[Array[Integer]]
        # @rbs @out: Array[Hash[Integer, bool]]
        # @rbs @reached: Integer
        # @rbs @colour: Array[Integer?]
        # @rbs @types: Array[Integer]
        # @rbs @of_type: Hash[Integer, Array[Integer]]
        # @rbs @freed: Hash[Integer, Array[Integer]]
        # @rbs @cursor: Hash[Integer, Integer]
        # @rbs @busy: Array[Integer?]
        # @rbs @stamp: Integer
        # @rbs @local: Hash[String, Integer]

        # Returns `{ value => local index }` for `values` (`[value, wasm type]`
        # pairs), and the wasm type of each local from `base`, the first
        # shared local.
        #: (IR::Function f, Array[[String, Integer]] values, Integer base) -> [Hash[String, Integer], Array[Integer]]
        def self.of(f, values, base) = new(f, values, base).assign

        #: (IR::Function f, Array[[String, Integer]] values, Integer base) -> void
        def initialize(f, values, base)
          @f = f
          @values = values
          @base = base
        end

        #: () -> [Hash[String, Integer], Array[Integer]]
        def assign
          number
          live
          colour
          [@local, @types]
        end

        private

        # Finds a number for each value, the block that defines it, each
        # block's successors and predecessors, and the index of the last
        # instruction that reads each value in its block.
        #: () -> void
        def number
          @id = {}
          @wasm = []
          @values.each do |v, t|
            @id[v] = @wasm.size
            @wasm << t
          end
          blocks = @f.blocks
          index = {} #: Hash[String, Integer]
          blocks.each_with_index { |b, bi| index[b.name] = bi }
          @home = Array.new(@wasm.size)
          @succ = []
          @pred = Array.new(blocks.size) { [] }
          @last = []
          @uses = []
          blocks.each_with_index do |b, bi|
            b.params.each { |v, _| (n = @id[v]) && @home[n] = bi }
            last = {} #: Hash[Integer, Integer]
            id = @id
            b.insts.each_with_index do |i, k|
              # Only a value has a number. An immediate or an entity name
              # has no number.
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

        # Sets `@in[block]`, the values live into the block, and
        # `@out[block]`, a Hash of the values live out of it. It walks back
        # from each use, one value at a time, so `seen` marks each block
        # once for each value: a value read in many blocks walks its range
        # once, not once for each block that reads it.
        #: () -> void
        def live
          n = @f.blocks.size
          @in = Array.new(n) { [] }
          @out = Array.new(n) { {} }
          seen = Array.new(n) #: Array[Integer?]
          work = [] #: Array[Integer]
          read_in = {} #: Hash[Integer, Array[Integer]]
          @uses.each_with_index { |used, bi| used.each { |v| (read_in[v] ||= []) << bi } }
          read_in.each do |v, blocks|
            home = @home[v]
            next if home.nil?

            blocks.each do |bi|
              next if home == bi || seen[bi] == v

              seen[bi] = v
              @in[bi] << v
              work << bi
              while (w = work.pop)
                @pred[w].each do |p|
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

        # Returns the postorder of the blocks reachable from the entry.
        # `@reached` is their count. The unreachable blocks come after them.
        #: () -> Array[Integer]
        def postorder
          seen = Array.new(@f.blocks.size, false)
          order = [] #: Array[Integer]
          stack = [[0, 0]] #: Array[[Integer, Integer]]
          seen[0] = true
          until stack.empty?
            frame = stack.last #: [Integer, Integer]
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

        #: () -> void
        def colour
          order = postorder
          @colour = Array.new(@wasm.size)
          @types = []
          # For each type: the locals of that type, the locals freed in the
          # current block, and a search cursor into the first list.
          # `@busy[local]` is the block that uses the local, so no data is
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
          @values.each { |v, _| @local[v] = @base + (@colour[@id[v]] or raise "#{@f.name}: #{v} has no local") }
        end

        # Gives locals to the values of one block. A local is free when no
        # live value uses it. Locals freed in this block go on a stack. A
        # cursor over each type's locals finds the others. Thus the cost of a
        # block depends on its live values, not on all locals of the function.
        #: (Integer bi) -> void
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
            # A jump writes every parameter, also a dead one. Thus each
            # parameter keeps its own local until the jump writes the last one.
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

        # A value that is not live out of its block frees its local at its
        # last read in the block. It frees the local one time only.
        #: (Integer n, Hash[Integer, Integer] last, Hash[Integer, bool] out) -> void
        def free_read(n, last, out)
          return if out.key?(n)

          last.delete(n)
          release(n)
        end

        #: (Integer n) -> void
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

        #: (Integer n) -> void
        def release(n)
          c = @colour[n] or return
          @busy[c] = nil
          @freed[@wasm[n]] << c
        end
      end
    end
  end
end
