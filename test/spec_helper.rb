# frozen_string_literal: true

# What a file under `test/spec/` requires. The specs hold zr to ruby by
# compiling a program and reading what it said, so they load the
# compiler; `test_helper` alone stays light, and a unit test that only
# reads a listing does not pay for a road it never takes.

require_relative "test_helper"
require_relative "support/spec"

# `zr "puts 1"` inside an `it` block, and `_(result).must_answer "1\n"`.
Minitest::Spec.include(Zr::Spec::DSL)
Minitest::Expectation.include(Zr::Spec::Expectation)


# Ahead of the workers: the kept binaries fit their bound, and the
# directory the workers write their binaries under is this process's
# to remove.
Zr::Spec::Binaries.trim
Zr::Spec.binaries_dir
