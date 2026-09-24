# frozen_string_literal: true

# A file under `test/spec/` requires this file. The specs compile a
# program and check its output against ruby, so they load the compiler.
# `test_helper` does not load the compiler. Thus a unit test that does
# not compile a program does not pay the load time.

require_relative "test_helper"
require_relative "support/spec"

# Lets a spec write `zr "puts 1"` inside an `it` block, and
# `_(result).must_answer "1\n"`.
Minitest::Spec.include(Zr::Spec::DSL)
Minitest::Expectation.include(Zr::Spec::Expectation)
Minitest::Spec.include(Zr::Spec::Baselined)


# Before the workers start: trim the kept binaries to their size limit.
# Then make the directory for the binaries of the workers. This process
# owns it and removes it.
Zr::Spec::Binaries.trim
Zr::Spec.binaries_dir
