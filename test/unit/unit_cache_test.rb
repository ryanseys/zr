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
  Unit = Struct.new(:source, :file, :internal, :hidden, :activates, :body)

  def unit(path: "/app/lib/b.rb", target: 1)
    body = [Zr::Hir::Require.new(:require_relative, "b", path, target, 1)]
    Unit.new("require_relative 'b'\n", "/app/main.rb", false, false, nil, body)
  end

  def key(unit, entries)
    cache = Zr::Cache::Unit.new(runtime: "rt", traced: 0, entries: entries)
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

  def test_a_require_nested_in_a_def_counts
    nested = unit
    nested.body = [[:def, [Zr::Hir::Require.new(:require, "b", "/app/lib/b.rb", 1, 3)]]]

    refute_equal key(nested, %w[main b]), key(nested, %w[main other])
  end
end
