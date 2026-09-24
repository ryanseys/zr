# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/native/build"

# The machine code of a file must not depend on what was compiled before
# it.
#
# Two programs that require the same file must write the same symbol
# names for it, then the same code, then the same data. The unit cache
# (lib/zr/unit_cache.rb) depends on this. Otherwise a cached unit
# contains names, symbol ids and literal slots that are correct only for
# the program that first compiled it.
class UnitBytesTest < Minitest::Test
  # A file with one of each item that makes a symbol or uses a site: a
  # method, an ivar, a constant, a symbol literal, a keyword, a global, a
  # block that reads a local outside it, and the three literals that use
  # a slot in the run-time table (a regexp, a range, and an integer too
  # wide for a Fixnum).
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

  # A file that the second program compiles first, so that everything
  # after it sees the symbol table and the site counter in a different state.
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

  def test_shared_file_compiles_to_the_same_code_in_two_programs
    Dir.mktmpdir("zr-unit-bytes-") do |dir|
      File.write(File.join(dir, "shared.rb"), SHARED)
      File.write(File.join(dir, "earlier.rb"), BEFORE)
      alone = unit_of(dir, "alone.rb", %(require_relative "shared"\np UnitBytesProbe::SHAPE\n))
      after = unit_of(dir, "after.rb", %(require_relative "earlier"\nrequire_relative "shared"\n) +
                                       %(p UnitBytesProbe::SHAPE\n))

      # Compare the code only. The data of a unit contains the numbers
      # that the link selected (the ids for the names that this file
      # introduced). The second program numbers more names before it, so
      # those words belong to the program, not to the file. The code
      # belongs to the file, and the cache returns the code.
      refute_empty alone, "the probe named nothing; the test no longer compiles what it thinks it does"
      assert_equal alone.keys.sort, after.keys.sort, "the file does not name what it makes the same way twice"
      alone.each { |name, made| assert_equal made, after[name], "#{name} came out differently in the second program" }
    end
  end

  # The same file compiled twice: the second build reads the unit back
  # from the cache, and must write what the first build wrote.
  def test_cached_unit_writes_the_same_bytes_as_the_first_build
    Dir.mktmpdir("zr-unit-cache-") do |dir|
      File.write(File.join(dir, "shared.rb"), SHARED)
      main = %(require_relative "shared"\np UnitBytesProbe.new(1).named(kind: :k)\n)
      cold = unit_of(dir, "cold.rb", main, data: true)
      warm = unit_of(dir, "warm.rb", main, data: true)

      refute_empty cold
      assert_equal cold, warm
    end
  end

  private

  # Everything the shared file made, by name: the machine code of each
  # function, and the section, bytes and relocations of each data object.
  # A unit gives its symbols a prefix of its own, which the name of the
  # probe's class body contains. This separates the symbols of the shared
  # file from those of the program and of any other unit.
  def unit_of(dir, main, source, data: false)
    path = File.join(dir, main)
    File.write(path, source)
    program = Zr::Native::Build.lower(source, path)
    body = program.functions.map(&:name).grep(/UnitBytesProbe/).first
    prefix = body&.slice(/zr_u[0-9a-f]+/) or return {}

    made = program.functions.select { |f| f.name.include?(prefix) }.to_h { |f| [f.name, [f.bytes, f.relocs]] }
    return made unless data

    program.data.select { |d| d.name.include?(prefix) }
           .each { |d| made[d.name] = [d.section, d.bytes, d.relocs] }
    made
  end
end
