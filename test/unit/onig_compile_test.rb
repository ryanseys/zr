# frozen_string_literal: true

require "test_helper"
require_relative "../support/harness/regexp_diff"

# Compiles every regexp in the test corpus with the core's compiler
# (lib/zr/runtime/core/regexp/onig/*) under this ruby. Each pattern that ruby
# compiles also compiles here, into a program String that the kernel
# reads. The program has the same number of groups as ruby's MatchData,
# and the names that ruby's Regexp#names returns. Each pattern that ruby
# refuses gets ruby's error message. The test prints the median compile
# time, because StringScanner and String methods compile a String
# argument on each call.
class OnigCompileTest < Minitest::Test
  Diff = Zr::Harness::RegexpDiff
  Pattern = Regexp.const_get(:Pattern)

  def patterns
    Dir[File.join(ROOT, "test/**/*.rb")].sort.flat_map { |path| Diff.harvest_file(path).first }.uniq
  end

  # The number of groups in a MatchData of `re`. An empty alternative
  # after the pattern forces a match.
  def groups_of(re)
    Regexp.new("(?:#{re.source})|", re.options).match("").size - 1
  rescue RegexpError, ArgumentError
    nil
  end

  def test_the_corpus_patterns_compile_as_ruby_compiles_them
    was = $VERBOSE
    $VERBOSE = nil
    times = []
    checked = 0
    patterns.each do |source, options|
      want = begin
        Regexp.new(source, options)
      rescue RegexpError, ArgumentError => e
        [e.class, e.message.b]
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      got = begin
        _, _, reg, = Pattern.compile(source.dup.freeze, options)
        reg
      rescue Regexp::Onig::Failure => e
        # Regexp raises the compiler's failure as a plain RegexpError.
        [RegexpError, e.message.b]
      rescue RegexpError, ArgumentError => e
        [e.class, e.message.b]
      end
      times << Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      label = "/#{source}/ options #{options}"
      if want.is_a?(Array) || got.is_a?(Array)
        assert_equal want, got, label
        next
      end

      program = Regexp::Onig::Program.pack(got)
      assert_operator program.bytesize, :>, 0, label
      assert_equal want.names, (got.name_table ? got.name_table.keys.map { |name| name.dup.force_encoding(want.encoding) } : []), label
      groups = groups_of(want)
      assert_equal groups, got.num_mem, label if groups
      checked += 1
    end
    assert_operator checked, :>, 500
    times.sort!
    puts format("\n%d patterns, compile median %.3f ms, p99 %.3f ms", times.size, times[times.size / 2] * 1000, times[times.size * 99 / 100] * 1000)
  ensure
    $VERBOSE = was
  end
end
