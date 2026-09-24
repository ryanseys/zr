# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../lib/zr/native/build"

# The unit cache fails closed on the entry names of other units. A
# `require` of a load-path file refers to the entry of that unit, whose
# name comes from the absolute path of the file. The same program
# compiled in another directory gives the unit a different name, so a
# unit kept from the first compile would call an entry that nothing
# defines. The second build must link.
class UnitCacheTest < Minitest::Test
  # One unit, as the key reads it: a plain program file.
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
  # A second unit that requires the first: its bytes refer to the entry
  # of the first unit, whose name comes from the absolute path of that file.
  USER = "require \"demo\"\nmodule User\n  VALUE = 2\nend\n"

  def test_program_links_with_units_cached_in_another_directory
    2.times do
      Dir.mktmpdir("zr-unit-cache-") do |dir|
        dir = File.realpath(dir)
        Dir.mkdir(File.join(dir, "lib"))
        File.write(File.join(dir, "lib/demo.rb"), DEMO)
        File.write(File.join(dir, "user.rb"), USER)
        File.write(File.join(dir, "main.rb"), MAIN)
        program = Dir.chdir(dir) { Zr::Native::Build.lower(MAIN, "main.rb") }
        bin = File.join(dir, "main")

        assert_nil Zr::Native::Build.program(program, bin, work: dir)
        assert_equal "42\n", IO.popen([bin], &:read)
      end
    end
  end

  def test_key_changes_with_the_entry_of_another_unit
    Dir.mktmpdir("zr-unit-cache-") do |dir|
      unit = StandIn.new
      keys = %w[one two].map do |entry|
        cache = Zr::UnitCache.new(dir: dir, runtime: "rt", table: "rt", traced: 0, entries: ["zr_toplevel_unit_0", entry])
        cache.send(:key, unit, "zr_toplevel_unit_0")
      end

      refute_equal keys[0], keys[1]
    end
  end
end
