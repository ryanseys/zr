# frozen_string_literal: true

source "https://rubygems.org"

# The stage-0 host is ruby 4.0.6 (.ruby-version), which is also the oracle
# every corpus program was recorded from. prism is the parser; minitest runs
# the repo's own checks. Both ship with ruby; pinning them here keeps every
# machine on one version.
gem "prism", "~> 1.9"
gem "minitest", "~> 6.0"
# The arm64 encoder the checks hold ours to. It is generated from the ARM
# specification, so it is the authority on an encoding; it builds its own
# methods with `class_eval` on strings, so it never enters a program.
gem "aarch64", "~> 3.0"

# Development only, and never part of a build or a check: the sampling
# profiler the compiler's own hot paths are measured with. Needs ruby
# 3.2.1 or later, which the stage-0 host is well past.
group :development do
  gem "vernier", "~> 1.0"
end
