# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/ze0/native/build"

# A file's machine code may not depend on what was compiled before it.
#
# Two programs that both require the same file must write the same
# bytes for it: the same function names, the same code, the same data.
# Until that holds there is nothing to cache, because a cached unit
# would carry symbol ids and site indices that only the program it was
# first compiled in agrees with (Phase 1.1 of the plan).
class UnitBytesTest < Minitest::Test
  # A file with one of each thing that names a symbol or takes a site:
  # a method, an ivar, a constant, a symbol literal, a keyword, a global
  # and a regexp literal, which holds a slot in the run-time table.
  SHARED = <<~'RUBY'
    class UnitBytesProbe
      SHAPE = :round

      def initialize(edge)
        @edge = edge
      end

      def named(kind:, sides: 3)
        [kind, sides, @edge, SHAPE, $unit_bytes_probe, /a(b)c/.match?("abc")]
      end
    end
  RUBY

  # A file the second program compiles first, so that everything after
  # it meets the symbol table and the site counter in a different state.
  BEFORE = <<~'RUBY'
    module UnitBytesEarlier
      FIRST = :earlier

      def self.count(over:)
        over.map { |x| /\d+/.match?(x.to_s) ? x.to_i : 0 }.sum
      end
    end
  RUBY

  def test_the_same_file_writes_the_same_bytes_in_two_programs
    Dir.mktmpdir("ze0-unit-bytes-") do |dir|
      File.write(File.join(dir, "shared.rb"), SHARED)
      File.write(File.join(dir, "earlier.rb"), BEFORE)
      alone = compile(dir, "alone.rb", %(require_relative "shared"\np UnitBytesProbe::SHAPE\n))
      after = compile(dir, "after.rb", %(require_relative "earlier"\nrequire_relative "shared"\np UnitBytesProbe::SHAPE\n))

      assert_equal alone.keys.sort, after.keys.sort, "the file's functions are not named the same in both programs"
      refute_empty alone, "the probe named no function; the test no longer compiles what it thinks it does"
      alone.each { |name, bytes| assert_equal bytes, after[name], "#{name} assembled differently in the second program" }
    end
  end

  private

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
