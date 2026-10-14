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
    class Promotion
      # @rbs @f: Function
      # @rbs @preds: Hash[String, Array[Block]]
      # @rbs @rename: Hash[String, String]
      # @rbs @last: Hash[String, Hash[String, String | Inst]]
      # @rbs @entering: Hash[String, Hash[String, String]]
      # @rbs @joins: Array[[String, Block, String]]
      # @rbs @incoming: Hash[String, Array[String]]
      # @rbs @sides: Hash[String, Array[Block]]
      # @rbs @work: Array[[String, Block, String]]

      #: (Function f) -> Function
      def self.run(f) = new(f).run

      #: (Function f) -> void
      def initialize(f)
        @f = f
      end

      #: () -> Function
      def run
        keys = candidates
        return @f if keys.empty?

        @preds = predecessors
        return @f if @preds[@f.entry_block.name].any?

        plan(keys)
        @sides = {}
        apply(keys)
        @f.place_before(@sides)
        rewrite(keys)
        rename_uses
        @f.changed!(:cfg)
      end

      private

      # The predecessors of each block, from the terminators that reach it.
      # A block that a `brif` reaches two times lists it two times.
      #: () -> Hash[String, Array[Block]]
      def predecessors
        preds = Hash.new { |h, k| h[k] = [] } #: Hash[String, Array[Block]]
        @f.blocks.each do |b|
          b.insts.last&.targets&.each { |name, _| preds[name] << b }
        end
        preds
      end

      # Finds the value of each read, and each parameter that a join needs,
      # for the variables in `keys`. `@rename` maps the result of a read to
      # the value that it reads.
      #: (Hash[String, String?] keys) -> void
      def plan(keys)
        @rename = {}
        @last = Hash.new { |h, k| h[k] = {} }
        @entering = Hash.new { |h, k| h[k] = {} }
        @joins = []
        @incoming = {}
        @work = []
        reads = [] #: Array[[String, Block, String]]
        @f.blocks.each { |b| walk(b, keys, @last[b.name], reads) }
        reads.each { |result, b, key| @rename[result] = entering(b, key, keys) }
        until @work.empty?
          param, b, key = @work.pop #: [String, Block, String]
          @incoming[param] = @preds[b.name].map { |p| leaving(p, key, keys) }
        end
        drop_trivial(keys)
      end

      # The value of the variable of `key` where control enters `b`.
      #: (Block b, String key, Hash[String, String?] keys) -> String
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
      #: (Block b, String key, Hash[String, String?] keys) -> String
      def leaving(b, key, keys)
        last = @last[b.name]
        return entering(b, key, keys) unless last.key?(key)

        left = last[key]
        left.is_a?(Inst) ? after(left, key) : left
      end

      # A parameter that gets one value from each edge (or only itself) is
      # that value. When the pass removes one, another can become trivial.
      #: (Hash[String, String?] keys) -> void
      def drop_trivial(keys)
        loop do
          dropped = false
          @joins.each do |param, _, key|
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

      #: (untyped v) -> untyped
      def resolve(v)
        v = @rename[v] while @rename.key?(v)
        v
      end

      # Adds the parameters of each join, and the value that each edge into
      # it passes. The pass first splits each `brif` edge.
      #: (Hash[String, String?] keys) -> void
      def apply(keys)
        @joins.each do |param, b, key|
          # A join has a read, so its variable has a type.
          type = keys.fetch(key) #: String
          b.params << [param, type]
          into = @preds[b.name]
          values = @incoming[param]
          into.each_with_index do |p, k|
            p = into[k] = split(p, b) if p.insts.last.op == :brif
            # Make a new Array; do not use `<<`, because two jumps can share it.
            edge = p.insts.last.targets[0]
            edge[1] = edge[1] + [values[k]]
          end
        end
      end

      # Makes a new block on the edge from the `brif` of `p` into `join`, so
      # that the edge is a jump that can pass the join parameters. `run`
      # places it before `join`, after the ones made before it.
      #: (Block p, Block join) -> Block
      def split(p, join)
        br = p.insts.last
        side = @f.unplaced_block
        (@sides[join.name] ||= []) << side
        side.insts << Inst.new(:jump, targets: [[join.name, []]])
        k = br.targets.index { |(name, _)| name == join.name } #: Integer
        br.targets[k] = [side.name, []]
        side
      end

      #: () -> void
      def rename_uses
        @f.blocks.each do |b|
          b.insts.each do |i|
            i.args.map! { |a| resolve(a) }
            i.targets&.each { |_, args| args.map! { |a| resolve(a) } }
          end
        end
      end
    end
  end
end
