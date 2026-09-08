# frozen_string_literal: true

require_relative "function"

module Ze0
  module IR
    # The checks every function passes before an emitter sees it: every
    # block ends in a terminator, every branch names a block and passes as
    # many arguments as it takes, every value used is defined once, and a
    # value is not used before its defining block in layout order. A
    # failure names the function and the instruction.
    module Verify
      class Error < StandardError; end

      module_function

      def check(f)
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
              next unless a.is_a?(String) && a.start_with?("v")
              raise Error, "#{f.name}: #{b.name} uses #{a}, which nothing defines" unless defined.key?(a)
            end
            (i.targets || []).each do |name, args|
              target = blocks[name] or raise Error, "#{f.name}: #{b.name} jumps to #{name}, which does not exist"
              if args.size != target.params.size
                raise Error, "#{f.name}: #{b.name} passes #{args.size} argument(s) to #{name}, which takes #{target.params.size}"
              end
            end
          end
        end
        f
      end

      def define(f, defined, v, block)
        raise Error, "#{f.name}: #{v} is defined twice" if defined.key?(v)

        defined[v] = block
      end
    end
  end
end
