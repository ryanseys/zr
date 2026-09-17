# frozen_string_literal: true

# The pure-Ruby prism against ruby's own C prism, file by file
# (lib/ze0/harness/prism_diff.rb).
#
#   ruby tools/prism_diff.rb --writer [--corpus NAMES] [--only GLOB]
#
# --writer: each C dump written again by Prism::Ruby::Dump, byte for byte.
# Corpora, comma-separated: fixtures and errors (prism 1.9.0's test/prism,
# extracted from ~/dev/prism into tmp/prism-1.9.0 on first use), rt, lib,
# test and vendor (ze0's own .rb files). The default is fixtures,errors.
# The exit status is 1 when any case differs.
require "fileutils"
require "optparse"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ze0/harness/prism_diff"

mode = nil
corpora = %w[fixtures errors]
only = nil
OptionParser.new do |o|
  o.on("--writer") { mode = :writer }
  o.on("--corpus NAMES") { |names| corpora = names.split(",") }
  o.on("--only GLOB") { |glob| only = glob }
end.parse!
abort "usage: ruby tools/prism_diff.rb --writer [--corpus NAMES] [--only GLOB]" unless mode

cases = Ze0::Harness::PrismDiff.cases(corpora, only: only)
failures = Ze0::Harness::PrismDiff.public_send(mode, cases)
failures.each { |name, why| puts "differs #{name}: #{why}" }
puts "#{cases.size - failures.size} of #{cases.size} cases match"
exit(failures.empty? ? 0 : 1)
