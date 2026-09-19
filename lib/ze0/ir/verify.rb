# frozen_string_literal: true

require_relative "function"
require_relative "types"

module Ze0
  module IR
    # The checks every function passes before an emitter sees it: every
    # block ends in a terminator, every branch names a block and passes as
    # many arguments as it takes, and every value used is defined once.
    # Under `strict` also: every use is dominated by its definition, and
    # every argument a jump carries has its parameter's type. A failure
    # names the function and the instruction.
    module Verify
      class Error < StandardError; end

      module_function

      def check(f, strict: false)
        blocks = f.blocks.to_h { |b| [b.name, b] }
        defined = {}
        f.blocks.each do |b|
          b.params.each { |v, _| define(f, defined, v, b.name) }
          b.insts.each { |i| i.results.each { |v| define(f, defined, v, b.name) } }
        end
        f.blocks.each do |b|
          raise Error, "#{f.name}: #{b.name} has no terminator" unless b.terminated?

          b.insts.each_with_index do |i, n|
            raise Error, "#{f.name}: #{b.name} has an instruction after its terminator" if n < b.insts.size - 1 && i.terminator?

            i.args.each do |a|
              next unless IR.value?(a)
              raise Error, "#{f.name}: #{b.name} uses #{a}, which nothing defines" unless defined.key?(a)
            end
            (i.targets || []).each do |name, args|
              target = blocks[name] or raise Error, "#{f.name}: #{b.name} jumps to #{name}, which does not exist"
              if args.size != target.params.size
                raise Error, "#{f.name}: #{b.name} passes #{args.size} argument(s) to #{name}, which takes #{target.params.size}"
              end
              raise Error, "#{f.name}: #{b.name} branches to #{name} with arguments" if i.op == :brif && !args.empty?
            end
          end
        end
        Strict.new(f, blocks).check if strict
        f
      end

      def define(f, defined, v, block)
        raise Error, "#{f.name}: #{v} is defined twice" if defined.key?(v)

        defined[v] = block
      end

      # Dominance and types. The dominator tree is Cooper, Harvey and
      # Kennedy's iterative one over a reverse postorder; a use in a block
      # the entry does not reach is not checked, since nothing runs it.
      class Strict
        def initialize(f, blocks)
          @f = f
          @blocks = blocks
        end

        def check
          types = Types.new(@f).all
          order = postorder.reverse
          number = order.each_with_index.to_h
          idom = dominators(order, number)
          defined_in = {}
          at = {}
          @f.blocks.each do |b|
            b.params.each { |v, _| defined_in[v] = b.name }
            b.insts.each_with_index do |i, n|
              i.results.each do |v|
                defined_in[v] = b.name
                at[v] = n
              end
            end
          end
          order.each do |b|
            b.insts.each_with_index do |i, n|
              i.args.each { |a| dominated(a, b, n, defined_in, at, idom, number) if IR.value?(a) }
              (i.targets || []).each do |name, args|
                args.each_with_index do |a, k|
                  dominated(a, b, n, defined_in, at, idom, number) if IR.value?(a)
                  want = @blocks.fetch(name).params[k][1]
                  got = types.fetch(a)
                  raise Error, "#{@f.name}: #{b.name} passes #{a} (#{got}) to #{name}, whose parameter is #{want}" if got != want
                end
              end
            end
          end
        end

        private

        # Whether the definition of `v` reaches its use at instruction
        # `n` of block `b`: in the same block before it, or in a block
        # that dominates `b`.
        def dominated(v, b, n, defined_in, at, idom, number)
          home = defined_in.fetch(v)
          if home == b.name
            return if at[v].nil? || at[v] < n

            raise Error, "#{@f.name}: #{b.name} uses #{v} before it is defined"
          end
          d = b.name
          d = idom[d] while d && d != home
          return if d

          raise Error, "#{@f.name}: #{b.name} uses #{v}, defined in #{home}, which does not dominate it"
        end

        def successors(b) = (b.insts.last&.targets || []).map(&:first)

        def postorder
          seen = {}
          out = []
          stack = [[@f.entry_block, 0]]
          seen[@f.entry_block.name] = true
          until stack.empty?
            b, k = stack.last
            next_names = successors(b)
            if k < next_names.size
              stack.last[1] += 1
              s = @blocks.fetch(next_names[k])
              next if seen[s.name]

              seen[s.name] = true
              stack << [s, 0]
            else
              stack.pop
              out << b
            end
          end
          out
        end

        # `{ block name => immediate dominator's name }`, the entry's nil.
        def dominators(order, number)
          preds = Hash.new { |h, k| h[k] = [] }
          order.each { |b| successors(b).each { |s| preds[s] << b.name } }
          idom = { @f.entry_block.name => @f.entry_block.name }
          changed = true
          while changed
            changed = false
            order.drop(1).each do |b|
              new = nil
              preds[b.name].each do |p|
                next unless idom.key?(p)

                new = new ? intersect(new, p, idom, number) : p
              end
              next if new.nil? || idom[b.name] == new

              idom[b.name] = new
              changed = true
            end
          end
          idom[@f.entry_block.name] = nil
          idom
        end

        def intersect(a, b, idom, number)
          until a == b
            a = idom[a] while number.fetch(@blocks.fetch(a)) > number.fetch(@blocks.fetch(b))
            b = idom[b] while number.fetch(@blocks.fetch(b)) > number.fetch(@blocks.fetch(a))
          end
          a
        end
      end
    end
  end
end
