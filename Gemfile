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
