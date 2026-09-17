# frozen_string_literal: true

# What a file under `test/spec/` requires. The specs hold ze0 to ruby by
# compiling a program and reading what it said, so they load the
# compiler; `test_helper` alone stays light, and a unit test that only
# reads a listing does not pay for a road it never takes.

require_relative "test_helper"
require_relative "support/spec"

# `ze0 "puts 1"` inside an `it` block, and `_(result).must_answer "1\n"`.
Minitest::Spec.include(Ze0::Spec::DSL)
Minitest::Expectation.include(Ze0::Spec::Expectation)

