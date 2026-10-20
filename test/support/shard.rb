# frozen_string_literal: true

require "zlib"

module Zr
  module Test
    # `ZR_TEST_SHARD=I/N` runs one Nth of the tests: each example whose
    # CRC-32 of "Class#method" is I - 1 modulo N. CI runs the N shards on
    # N machines (.github/workflows/ci.yml, `full`). The hash of each name
    # gives the same split on every machine and keeps the shards about
    # even. The program tier asks the same filter, so a shard builds only
    # its own programs (test/programs_test.rb).
    module Shard
      module_function

      # `[index, count]` from `spec` ("2/4"), or nil without one.
      #: (String? spec) -> [Integer, Integer]?
      def parse(spec)
        return nil if spec.nil? || spec.empty?

        index, count = spec.match(%r{\A(\d+)/(\d+)\z})&.captures&.map(&:to_i)
        unless index && count && count.positive? && index.between?(1, count)
          raise ArgumentError, "ZR_TEST_SHARD is #{spec.inspect}. Set it to I/N with 1 <= I <= N, for example ZR_TEST_SHARD=2/4."
        end

        [index, count]
      end

      # Whether the example `name` of `klass` is in shard `index` of `count`.
      #: (String klass, String name, Integer index, Integer count) -> bool
      def mine?(klass, name, index, count) = Zlib.crc32("#{klass}##{name}") % count == index - 1

      # Keeps only this shard's examples in minitest's filter.
      module Filter
        def filter_runnable_methods(options = {})
          index, count = Shard.parse(ENV.fetch("ZR_TEST_SHARD", nil))
          return super unless count

          super.select { |name| Shard.mine?(to_s, name, index, count) }
        end
      end
    end
  end
end

Minitest::Runnable.singleton_class.prepend(Zr::Test::Shard::Filter)
