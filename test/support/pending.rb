# frozen_string_literal: true

require_relative "baseline"

module Zr
  module Test
    # The minitest tests that test/baselines/upgrade.txt lists: the ones
    # that a new ruby changed and zr does not match yet. A key is the
    # test's file and method, `test/ext/basics_test.rb#test_name`.
    #
    # A listed test that fails is a skip that gives the reason. A listed
    # test that passes fails the run, so that each fix removes its line.
    module Pending
      module_function

      def reasons = @reasons ||= Baseline.upgrade.select { |key, _| key.include?("#") }

      # The key of `test`, an instance of a Minitest::Test.
      def key(test)
        file = test.method(test.name).source_location&.first or return nil
        "#{file.delete_prefix("#{File.expand_path("../..", __dir__)}/")}##{test.name}"
      end

      # Runs after each test, with its result known.
      module Hook
        def after_teardown
          super
          key = Pending.key(self) or return
          why = Pending.reasons[key] or return

          if failures.any? { |failure| !failure.is_a?(Minitest::Skip) }
            self.failures = [Minitest::Skip.new("pending in test/baselines/upgrade.txt: #{why}")]
          elsif failures.empty?
            failures << Minitest::Assertion.new("#{key} passes now: remove its line from test/baselines/upgrade.txt")
          end
        end
      end
    end
  end
end
