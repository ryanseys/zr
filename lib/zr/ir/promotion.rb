# frozen_string_literal: true

require_relative "inst"

module Zr
  module IR
    # Promotes memory to SSA values in a finished function. This is the
    # shared part of `Mem2Reg` (a stack slot) and `Statics` (a static word
    # of the kernel).
    #
    # A word that the function reads and writes whole, through a known
    # address, is a variable. Each read gets the value of the last write
    # before it. A block that different writes reach takes the value as a
    # parameter. The subclass defines what a write is: `walk` gives, for
    # each block, the value that each write leaves and the reads before
    # the first write; `initial` gives the value for a read that no write
    # reaches; `rewrite` removes the replaced instructions.
    #
    # The algorithm is from Braun et al. The CFG is complete, so all blocks
    # are sealed at the start. A read with no earlier write in its block
    # reads from the predecessors. A block with more than one predecessor
    # makes a parameter first. A parameter that gets the same value from
    # each edge is that value.
    #
    # A `brif` has no arguments. So when a join takes a parameter, the pass
    # splits each `brif` edge into it: a new block before the join that
    # jumps to it.
    #
    # The walks use `while` loops, because this runs on each instruction of
    # each function, and each block call costs a frame in the compiled
    # compiler.
    class Promotion
      def self.run(f) = new(f).run

      def initialize(f)
        @f = f
      end

      def run
        keys = candidates
        return @f if keys.empty?

        @preds = predecessors
        return @f if @preds[@f.entry_block.name].any?

        plan(keys)
        apply(keys)
        rewrite(keys)
        rename_uses
        @f.changed!(:cfg)
      end

      private

      # The predecessors of each block, from the terminators that reach it.
      # A block that a `brif` reaches two times lists it two times.
      def predecessors
        preds = Hash.new { |h, k| h[k] = [] }
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          b = blocks[bi]
          targets = b.insts.last&.targets
          if targets
            k = 0
            while k < targets.size
              preds[targets[k][0]] << b
              k += 1
            end
          end
          bi += 1
        end
        preds
      end

      # Finds the value of each read, and each parameter that a join needs,
      # for the variables in `keys`. `@rename` maps the result of a read to
      # the value that it reads.
      def plan(keys)
        @rename = {}
        @last = Hash.new { |h, k| h[k] = {} }
        @entering = Hash.new { |h, k| h[k] = {} }
        @joins = []
        @incoming = {}
        @work = []
        reads = []
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          b = blocks[bi]
          walk(b, keys, @last[b.name], reads)
          bi += 1
        end
        r = 0
        while r < reads.size
          result, b, key = reads[r]
          @rename[result] = entering(b, key, keys)
          r += 1
        end
        until @work.empty?
          param, b, key = @work.pop
          @incoming[param] = @preds[b.name].map { |p| leaving(p, key, keys) }
        end
        drop_trivial(keys)
      end

      # The value of the variable of `key` where control enters `b`.
      def entering(b, key, keys)
        seen = @entering[key]
        return seen[b.name] if seen.key?(b.name)

        from = @preds[b.name]
        seen[b.name] = case from.size
                       when 0 then initial(key, keys.fetch(key))
                       when 1 then leaving(from[0], key, keys)
                       else
                         param = @f.value
                         @joins << [param, b, key]
                         @work << [param, b, key]
                         param
                       end
      end

      # The value of the variable of `key` where control leaves `b`. This is
      # what the last write in `b` left (a value, or the instruction after
      # which the subclass loads again), or else the value at entry.
      def leaving(b, key, keys)
        last = @last[b.name]
        return entering(b, key, keys) unless last.key?(key)

        left = last[key]
        left.is_a?(Inst) ? after(left, key) : left
      end

      # A parameter that gets one value from each edge (or only itself) is
      # that value. When the pass removes one, another can become trivial.
      def drop_trivial(keys)
        loop do
          dropped = false
          j = 0
          while j < @joins.size
            param, _, key = @joins[j]
            j += 1
            next if @rename.key?(param)

            others = @incoming[param].map { |v| resolve(v) }.uniq
            others.delete(param)
            next if others.size > 1

            @rename[param] = others[0] || initial(key, keys.fetch(key))
            dropped = true
          end
          break unless dropped
        end
        @joins.reject! { |param, _, _| @rename.key?(param) }
      end

      def resolve(v)
        v = @rename[v] while @rename.key?(v)
        v
      end

      # Adds the parameters of each join, and the value that each edge into
      # it passes. The pass first splits each `brif` edge.
      def apply(keys)
        j = 0
        while j < @joins.size
          param, b, key = @joins[j]
          b.params << [param, keys.fetch(key)]
          into = @preds[b.name]
          values = @incoming[param]
          k = 0
          while k < into.size
            p = into[k]
            p = into[k] = split(p, b) if p.insts.last.op == :brif
            # Make a new Array; do not use `<<`, because two jumps can share it.
            edge = p.insts.last.targets[0]
            edge[1] = edge[1] + [values[k]]
            k += 1
          end
          j += 1
        end
      end

      # Makes a new block on the edge from the `brif` of `p` into `join`, so
      # that the edge is a jump that can pass the join parameters.
      def split(p, join)
        br = p.insts.last
        side = @f.block_before(join)
        side.insts << Inst.new(:jump, targets: [[join.name, []]])
        k = br.targets.index { |(name, _)| name == join.name }
        br.targets[k] = [side.name, []]
        side
      end

      def rename_uses
        blocks = @f.blocks
        bi = 0
        while bi < blocks.size
          insts = blocks[bi].insts
          n = 0
          while n < insts.size
            i = insts[n]
            i.args.map! { |a| resolve(a) }
            targets = i.targets
            if targets
              k = 0
              while k < targets.size
                targets[k][1].map! { |a| resolve(a) }
                k += 1
              end
            end
            n += 1
          end
          bi += 1
        end
      end
    end
  end
end
