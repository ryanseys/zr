# frozen_string_literal: true

source "https://rubygems.org"

# ze0's own dependencies are in ze0.gemspec. The stage-0 host is ruby
# 4.0.6 (.ruby-version), which is also the oracle every corpus program
# was recorded from.
gemspec

group :development, :test do
  gem "rake", "~> 13.0"
  # Runs `bin/ze0 check`.
  gem "minitest", "~> 6.0"
  # The arm64 encoder the checks hold ours to. It is generated from the ARM
  # specification, so it is the authority on an encoding; it builds its own
  # methods with `class_eval` on strings, so it never enters a program.
  gem "aarch64", "~> 3.0"
  # Obj::JIT's in-process host for the checks. A bundled gem, not a default
  # one, in ruby 4.
  gem "fiddle", "~> 1.1"
end

# Never part of a build or a check: the sampling profiler the compiler's
# own hot paths are measured with.
group :development do
  gem "vernier", "~> 1.0"
end
