# frozen_string_literal: true

source "https://rubygems.org"

# zr's own dependencies are in zr.gemspec. zr runs on ruby 4.0.6
# (.ruby-version), which is also the ruby that every test's expected
# output comes from.
gemspec

group :development, :test do
  gem "rake", "~> 13.0"
  # The test framework. `bin/test` runs it.
  gem "minitest", "~> 6.0"
  # The slowest-tests report (SLOW=1), and the JUnit file CI shows a
  # failure from.
  gem "minitest-reporters", "~> 1.8"
  # The arm64 encoder the checks hold ours to. It is generated from the ARM
  # specification, so it is the authority on an encoding; it builds its own
  # methods with `class_eval` on strings, so it never enters a program.
  gem "aarch64", "~> 3.0"
  # Obj::JIT's in-process host for the checks. A bundled gem, not a default
  # one, in ruby 4.
  gem "fiddle", "~> 1.1"
  # The clock `rake bench` and `rake compile` measure with: `Benchmark.measure`
  # gives a child's user and system time beside the wall clock. A bundled
  # gem too, so it is named here to be required under bundler.
  gem "benchmark", "~> 0.5"
end

# Not part of a build or a test run.
group :development do
  # The sampling profiler for the compiler's hot paths.
  gem "vernier", "~> 1.0"
  # `rake lint`: RuboCop's Lint cops only (.rubocop.yml).
  gem "rubocop", "~> 1.89", require: false
end
