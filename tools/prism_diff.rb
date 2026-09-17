# frozen_string_literal: true

# The pure-Ruby prism against ruby's own C prism, file by file
# (lib/ze0/harness/prism_diff.rb).
#
#   ruby tools/prism_diff.rb --writer [--corpus NAMES] [--only GLOB]
#   ruby tools/prism_diff.rb --lex [--states] [--corpus NAMES] [--only GLOB] [--show N]
#
# --writer: each C dump written again by Prism::Ruby::Dump, byte for byte.
# --lex: the lexer alone against Prism.lex's token types and ranges (and
# with --states, lex states); cases in a lex mode not yet written are
# counted apart.
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
states = false
show = 20
OptionParser.new do |o|
  o.on("--writer") { mode = :writer }
  o.on("--lex") { mode = :lex }
  o.on("--states") { states = true }
  o.on("--corpus NAMES") { |names| corpora = names.split(",") }
  o.on("--only GLOB") { |glob| only = glob }
  o.on("--show N", Integer) { |n| show = n }
end.parse!
abort "usage: ruby tools/prism_diff.rb --writer|--lex [--states] [--corpus NAMES] [--only GLOB] [--show N]" unless mode

diff = Ze0::Harness::PrismDiff
cases = diff.cases(corpora, only: only)
unsupported = 0
failures =
  case mode
  when :writer then diff.writer(cases)
  when :lex then diff.lex(cases, states: states).tap { |_, count| unsupported = count }.first
  end
failures.first(show).each { |name, why| puts "differs #{name}: #{why}" }
puts "#{cases.size - failures.size - unsupported} of #{cases.size} cases match, #{failures.size} differ, #{unsupported} unsupported"
exit(failures.empty? ? 0 : 1)
