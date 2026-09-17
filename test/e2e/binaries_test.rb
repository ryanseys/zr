# frozen_string_literal: true

require "test_helper"
require "support/e2e"

# Whole programs through a real link. Each one is a `.rb` file under
# `test/e2e/<suite>/<area>/` carrying ruby's answer beneath `__END__`,
# built by the CLI in its own process and run as a binary.
#
# A build is a child process of its own that is allowed as much as
# three gigabytes, so this tier runs fewer at a time than the specs,
# which build in the worker itself.
Minitest.parallel_executor = Ze0::Test::ForkPool.new(size: Integer(ENV.fetch("MT_CPU", 4)))

class BinariesTest < Minitest::Test
  include Ze0::E2E::DSL

  Ze0::E2E.define(self)
end
