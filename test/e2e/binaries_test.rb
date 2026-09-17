# frozen_string_literal: true

require "test_helper"
require "support/e2e"

# Whole programs through a real link. Each one is a `.rb` file under
# `test/e2e/<suite>/<area>/` carrying ruby's answer beneath `__END__`,
# built by the CLI in its own process and run as a binary.
#
# shards: 4
#
# A build is a child of its own, so this file's heap hardly moves; what
# the shards buy is four builds at once. The supervisor reads the count
# above and starts a process for each, handing it `ZE0_SHARD=2/4`.
class BinariesTest < Minitest::Test
  include Ze0::E2E::DSL

  Ze0::E2E.define(self)
end
