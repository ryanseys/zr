# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/ze0/native/build"

# A file's machine code may not depend on what was compiled before it.
#
# Two programs that both require the same file must write the same
# names for it, and then the same bytes. Until that holds there is
# nothing to cache, because a cached unit would carry names, symbol ids
# and site indices that only the program it was first compiled in
# agrees with (Phase 1.1 of the plan).
class UnitBytesTest < Minitest::Test
  # A file with one of each thing that names a symbol or takes a site:
  # a method, an ivar, a constant, a symbol literal, a keyword, a
  # global, a block that reaches a local outside it, and the three
  # literals that hold a slot in the run-time table -- a regexp, a
  # range and an integer too wide for a Fixnum.
  SHARED = <<~'RUBY'
    class UnitBytesProbe
      SHAPE = :round

      def initialize(edge)
        @edge = edge
      end

      def named(kind:, sides: 3)
        seen = []
        (1..sides).each { |n| seen << [n, kind, @edge, SHAPE, $unit_bytes_probe] }
        [seen, /a(b)c/.match?("abc"), 12_345_678_901_234_567_890_123]
      end
    end
  RUBY

  # A file the second program compiles first, so that everything after
  # it meets the symbol table and the site counter in a different state.
  BEFORE = <<~'RUBY'
    module UnitBytesEarlier
      FIRST = :earlier

      def self.count(over:)
        total = 0
        over.each { |x| total += (/\d+/.match?(x.to_s) ? x.to_i : 0) }
        [total, (0...9), 98_765_432_109_876_543_210_987]
      end
    end
  RUBY

  def test_the_same_file_names_its_functions_the_same_in_two_programs
    alone, after = two_programs
    refute_empty alone, "the probe named no function; the test no longer compiles what it thinks it does"
    assert_equal alone.keys.sort, after.keys.sort
  end

  def test_the_same_file_writes_the_same_bytes_in_two_programs
    alone, after = two_programs
    alone.each { |name, bytes| assert_equal bytes, after[name], "#{name} assembled differently in the second program" }
  end

  private

  # The shared file's `{name => bytes}` in a program that requires it
  # alone, and in one that requires another file before it.
  def two_programs
    Dir.mktmpdir("ze0-unit-bytes-") do |dir|
      File.write(File.join(dir, "shared.rb"), SHARED)
      File.write(File.join(dir, "earlier.rb"), BEFORE)
      [compile(dir, "alone.rb", %(require_relative "shared"\np UnitBytesProbe::SHAPE\n)),
       compile(dir, "after.rb", %(require_relative "earlier"\nrequire_relative "shared"\np UnitBytesProbe::SHAPE\n))]
    end
  end

  # `{name => bytes}` for every function the shared file wrote, in a
  # program whose main file is `main`.
  def compile(dir, main, source)
    path = File.join(dir, main)
    File.write(path, source)
    program = Ze0::Native::Build.lower(source, path)
    program.functions.select { |f| f.name.include?("UnitBytesProbe") || f.name.include?("named") }
           .to_h { |f| [f.name, f.bytes] }
  end
end
