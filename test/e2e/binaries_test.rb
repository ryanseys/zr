# frozen_string_literal: true

require "test_helper"
require "support/e2e"

# Whole programs through a real link. Each program is a `.rb` file under
# `test/e2e/<suite>/<area>/`. The CLI builds it in a separate process,
# and the test runs the binary. The expected output from ruby is next to
# the program: `<name>.out`, and `<name>.err` and `<name>.status` when
# they are not empty. `rake record` writes them. `Zr::E2E::HOW` gives the
# arguments and limits of the programs that need them.
#
# A build is a separate process that can use up to 3 GB. Thus this tier
# runs fewer programs at one time than the spec tier, which builds in
# the worker.
Minitest.parallel_executor = Zr::Test::ForkPool.new(size: Integer(ENV.fetch("MT_CPU", 4)))

class BinariesTest < Minitest::Test
  include Zr::E2E::DSL

  # A build and a run can each take `E2E::LIMIT` seconds. The pool must
  # wait for both, or it kills the worker first and the build continues
  # in a separate process group.
  def self.deadline = (2 * Zr::E2E::LIMIT) + 30

  Zr::E2E.define(self)
end
