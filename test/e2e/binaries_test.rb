# frozen_string_literal: true

require "test_helper"
require "support/e2e"

# Whole programs through a real link. Each one is a `.rb` file under
# `test/e2e/<suite>/<area>/` -- a program and nothing else -- built by
# the CLI in its own process and run as a binary. What ruby answered
# sits beside it: `<name>.out`, and `<name>.err` and `<name>.status`
# when there is something to say. `rake record` writes them, and
# `Zr::E2E::HOW` says what the few that need arguments need.
#
# A build is a child process of its own that is allowed as much as
# three gigabytes, so this tier runs fewer at a time than the specs,
# which build in the worker itself.
Minitest.parallel_executor = Zr::Test::ForkPool.new(size: Integer(ENV.fetch("MT_CPU", 4)))

class BinariesTest < Minitest::Test
  include Zr::E2E::DSL

  Zr::E2E.define(self)
end
