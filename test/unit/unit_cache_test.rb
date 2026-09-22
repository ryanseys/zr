# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/ze0/native/build"

# The unit cache fails closed on the other units' names. A `require` of
# a load-path file spells that unit's entry, which is made from the
# file's absolute path; the same program compiled in another directory
# names the unit otherwise, and a unit kept from the first compile
# would call an entry nothing defines. The second build must link.
class UnitCacheTest < Minitest::Test
  # One unit as the key reads it: a plain program file.
  class StandIn
    def source = "puts 1\n"
    def file = "a.rb"
    def activates = false
    def internal = false
    def hidden = false
  end

  MAIN = <<~'RUBY'
    $LOAD_PATH.unshift(File.join(__dir__, "lib"))
    require "demo"
    require_relative "user"
    puts Demo::VALUE + User::VALUE
  RUBY
  DEMO = "module Demo\n  VALUE = 40\nend\n"
  # A second unit that requires the first: its bytes spell the first
  # unit's entry, which is made from that file's absolute path.
  USER = "require \"demo\"\nmodule User\n  VALUE = 2\nend\n"

  def test_a_program_links_in_a_second_directory_after_its_units_were_kept_in_a_first
    2.times do
      Dir.mktmpdir("ze0-unit-cache-") do |dir|
        dir = File.realpath(dir)
        Dir.mkdir(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/demo.rb"), DEMO)
        File.write(File.join(dir, "user.rb"), USER)
        File.write(File.join(dir, "main.rb"), MAIN)
        program = Dir.chdir(dir) { Ze0::Native::Build.lower(MAIN, "main.rb") }
        bin = File.join(dir, "main")

        assert_nil Ze0::Native::Build.program(program, bin, work: dir)
        assert_equal "42\n", IO.popen([bin], &:read)
      end
    end
  end

  def test_the_key_moves_with_another_units_entry
    Dir.mktmpdir("ze0-unit-cache-") do |dir|
      unit = StandIn.new
      keys = %w[one two].map do |entry|
        cache = Ze0::UnitCache.new(dir: dir, runtime: "rt", table: "rt", traced: 0, entries: ["zr_toplevel_unit_0", entry])
        cache.send(:key, unit, "zr_toplevel_unit_0")
      end

      refute_equal keys[0], keys[1]
    end
  end
end
