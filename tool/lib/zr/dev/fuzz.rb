# frozen_string_literal: true

require "digest"
require_relative "../dev"
require_relative "suite"
require_relative "../../../../lib/zr/diff"
require_relative "../../../../lib/zr/timing"
require_relative "../../../../lib/zr/native/parallel"
require_relative "../../../../test/support/harness/child"
require_relative "../../../../test/support/harness/reference"
require_relative "../../../../test/support/workers"

module Zr
  module Dev
    # The parts of `zr-dev fuzz` (tool/fuzzer.rb), a differential fuzzer:
    # it writes Ruby programs, runs each one under ruby and as a zr
    # binary, and keeps each difference as a small case below log/fuzz.
    module Fuzz
      DIR = File.join(__dir__, "fuzz")

      # The version of the fuzzer: a digest of its files. A seed gives the
      # same program only at the same version.
      VERSION = Digest::SHA256.hexdigest(Dir[File.join(DIR, "**/*.rb")].sort.map { |f| File.binread(f) }.join)[0, 12]
    end
  end
end

require_relative "fuzz/verdict"
require_relative "fuzz/known"
require_relative "fuzz/store"
require_relative "fuzz/builder_client"
require_relative "fuzz/oracle"
require_relative "fuzz/corpus"
require_relative "fuzz/reducer"
require_relative "fuzz/mutator"
require_relative "fuzz/triage"
require_relative "fuzz/engine"
