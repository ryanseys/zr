# frozen_string_literal: true

require_relative "inst"

module Zr
  module IR
    # Memory to SSA values, over a finished function: what `Mem2Reg`
    # (a stack slot) and `Statics` (a static word of the kernel) share.
    #
    # A word the function reads and writes whole, through an address it
    # can tell, is a variable. Each read is then the value the last
    # write on the way there put, and a block that different writes
    # reach takes that value as a parameter. What counts as a write is
    # the subclass's to say: `walk` names, block by block, the value
    # each write leaves and the reads no write in the block precedes;
    # `initial` answers a read no write reaches at all; `rewrite` takes
    # the instructions the values replace out.
    #
    # The construction is Braun et al.'s, over a CFG that is already
    # complete, so every block is sealed from the start: a read with no
    # write ahead of it in its block asks its predecessors, a block with
    # several makes a parameter first, and a parameter every edge gives
    # the same value is that value.
    #
    # A `brif` carries no arguments, so an edge one enters a join by is
    # split when the join takes a parameter: a block of its own that
    # jumps on, laid out before the join so it falls into it.
    #
    # The walks over the blocks and their instructions are `while`
    # loops: this runs over every instruction of every function, and a
    # block call costs the compiled compiler a frame each.
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

      # Every block's predecessors, by the terminators that reach it: a
      # block a `brif` reaches twice lists it twice.
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

      # Every read's value, and every parameter a join needs, for the
      # variables in `keys`: `@rename` maps a read's result to what it
      # reads.
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

      # The value of `key`'s variable where control enters `b`.
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

      # The value of `key`'s variable where control leaves `b`: what
      # the last write in `b` left -- a value, or the instruction after
      # which the subclass reads it afresh -- else what entered.
      def leaving(b, key, keys)
        last = @last[b.name]
        return entering(b, key, keys) unless last.key?(key)

        left = last[key]
        left.is_a?(Inst) ? after(left, key) : left
      end

      # A parameter every edge gives one value, or only itself, is that
      # value; taking one away can make another trivial.
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

      # Each join's parameters, and the value every edge into it
      # carries; an edge a `brif` takes is split first.
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
            # A new Array and not `<<`: two jumps may share one.
            edge = p.insts.last.targets[0]
            edge[1] = edge[1] + [values[k]]
            k += 1
          end
          j += 1
        end
      end

      # A block of its own on the edge `p`'s `brif` takes into `join`, so
      # that the edge is a jump that can carry the join's parameters.
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
