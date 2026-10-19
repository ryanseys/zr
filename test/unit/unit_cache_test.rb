# frozen_string_literal: true
# zr-test: runtime

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

  # A unit as the key reads it, with a require of the unit at index 1.
  Unit = Struct.new(:source, :file, :internal, :hidden, :activates, :body, :context)

  def unit(path: "/app/lib/b.rb", target: 1, context: [0, 0, 0, 0])
    body = [Zr::Hir::Require.new(:require_relative, "b", path, target, 1)]
    Unit.new("require_relative 'b'\n", "/app/main.rb", false, false, nil, body, context)
  end

  def key(unit, entries, switches: "")
    cache = Zr::Cache::Unit.new(runtime: "rt", traced: 0, plain_new: 0, entries: entries, switches: switches)
    cache.send(:key, unit, "zr_toplevel_unit_0")
  end

  # A file added elsewhere in the program does not lower this unit again.
  def test_an_entry_the_unit_does_not_reach_leaves_the_key
    assert_equal key(unit, %w[main b]), key(unit, %w[main b c d])
  end

  def test_the_entry_of_a_reached_unit_is_in_the_key
    refute_equal key(unit, %w[main b]), key(unit, %w[main other])
  end

  def test_the_path_of_a_reached_unit_is_in_the_key
    refute_equal key(unit(path: "/app/lib/b.rb"), %w[main b]), key(unit(path: "/app/vendor/b.rb"), %w[main b])
  end

  # The same source lowers another way for the program's own file than
  # for a library's: a require of rubygems reads which it is.
  def test_the_facts_of_the_build_that_shaped_the_unit_are_in_the_key
    refute_equal key(unit(context: [0, 0, 0, 0]), %w[main b]), key(unit(context: [1, 0, 0, 0]), %w[main b])
  end

  # Gems off or frozen string literals change the HIR of every file.
  def test_the_switches_that_shape_every_file_are_in_the_key
    off = Zr::Hir::Switches.new(gems: false).unit_key
    frozen = Zr::Hir::Switches.new(frozen_string_literal: true).unit_key

    refute_equal key(unit, %w[main b], switches: Zr::Hir::Switches::NONE.unit_key), key(unit, %w[main b], switches: off)
    refute_equal key(unit, %w[main b], switches: Zr::Hir::Switches::NONE.unit_key), key(unit, %w[main b], switches: frozen)
  end

  # The `-e` text and the main file's switches stay out: a new `ruby -e`
  # child lowers no library again.
  def test_the_switches_of_the_main_file_alone_leave_the_key
    assert_equal Zr::Hir::Switches::NONE.unit_key, Zr::Hir::Switches.new(prelude: "p 1", inline: true).unit_key
  end

  def test_a_require_nested_in_a_def_counts
    nested = unit
    nested.body = [[:def, [Zr::Hir::Require.new(:require, "b", "/app/lib/b.rb", 1, 3)]]]

    refute_equal key(nested, %w[main b]), key(nested, %w[main other])
  end
end
