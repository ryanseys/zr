# frozen_string_literal: true

source "https://rubygems.org"

# zr's own dependencies are in zr.gemspec. The stage-0 host is ruby
# 4.0.6 (.ruby-version), which is also the oracle every corpus program
# was recorded from.
gemspec

group :development, :test do
  gem "rake", "~> 13.0"
  # The test framework. `rake test:*` is `Minitest::TestTask`, and the
  # `minitest` command runs one file or one example.
  gem "minitest", "~> 6.0"
  # A progress bar with an ETA, because the spec tier runs for minutes,
  # and the JUnit file CI renders a failure from.
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

# Never part of a build or a check: the sampling profiler the compiler's
# own hot paths are measured with.
group :development do
  gem "vernier", "~> 1.0"
end
