# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/native/build"

# A file's machine code may not depend on what was compiled before it.
#
# Two programs that both require the same file must write the same
# names for it, then the same code, then the same data. That is what
# makes a unit cache possible at all (lib/zr/unit_cache.rb): a cached
# unit would otherwise carry names, symbol ids and literal slots that
# only the program it was first compiled in agrees with.
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

  def test_the_same_file_writes_the_same_names_code_and_data_in_two_programs
    Dir.mktmpdir("zr-unit-bytes-") do |dir|
      File.write(File.join(dir, "shared.rb"), SHARED)
      File.write(File.join(dir, "earlier.rb"), BEFORE)
      alone = unit_of(dir, "alone.rb", %(require_relative "shared"\np UnitBytesProbe::SHAPE\n))
      after = unit_of(dir, "after.rb", %(require_relative "earlier"\nrequire_relative "shared"\n) +
                                       %(p UnitBytesProbe::SHAPE\n))

      # The code and nothing else. A unit's data holds the numbers the
      # link chose -- the ids for the names this file introduced -- and
      # the second program numbers more names before it, so those words
      # are the program's and not the file's. The code is the file's,
      # and it is what a cache would hand back.
      refute_empty alone, "the probe named nothing; the test no longer compiles what it thinks it does"
      assert_equal alone.keys.sort, after.keys.sort, "the file does not name what it makes the same way twice"
      alone.each { |name, made| assert_equal made, after[name], "#{name} came out differently in the second program" }
    end
  end

  # The same file compiled twice in a row: the second build reads the
  # unit back from the cache, and must write what the first one wrote.
  def test_a_build_that_reads_a_unit_back_writes_what_the_first_build_wrote
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

  # Everything the shared file made, by name: each function's machine
  # code, and each data object's section, bytes and relocations. A unit
  # names what it makes from a prefix of its own, which the probe's
  # class body carries, so this tells the shared file's symbols from
  # the program's own and from any other unit's.
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
