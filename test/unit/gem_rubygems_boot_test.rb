# frozen_string_literal: true

# zr-test: runtime
require "test_helper"
require "zr/gem_set"
require "zr/hir"

# When a program boots rubygems: ruby loads it before the first line, so
# a require of it returns false wherever it is, and Gem is there before
# any file that uses it.
class GemRubygemsBootTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("zr-gem-boot-")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # A gem's own require of rubygems boots it with the preludes, as one
  # in a file of the program does. Else rubygems would load where the gem
  # requires it, and Gem would be new after the gem's require.
  def test_a_gems_require_of_rubygems_boots_rubygems_before_the_first_line
    lib = File.join(@dir, "boots", "lib")
    FileUtils.mkdir_p(lib)
    File.write(File.join(lib, "boots.rb"), "require 'rubygems'\nmodule Boots; end\n")
    gems = Zr::GemSet.new([Zr::GemSet::Entry.new(name: "boots", version: "1.0.0", roots: [lib], refusal: nil, source: "installed", requested: true)])

    hir = Zr::Hir.build(%(require "boots"\n), File.join(@dir, "main.rb"), Zr::BuildOptions.new(gem_set: gems))

    assert_equal %w[rubygems bundled_gems zr/gem_manifest], preludes(hir).grep(/gem/)
    boots = hir.units.find { |unit| unit.file.end_with?("/boots.rb") }
    assert_equal Zr::Hir::Literal.new(false, 1), boots.body.stmts.first, "the gem's require returns false"
  end

  def test_a_program_that_neither_uses_nor_requires_rubygems_does_not_boot_it
    hir = Zr::Hir.build(%(p 1\n), File.join(@dir, "main.rb"))

    refute_includes preludes(hir), "rubygems"
  end

  private

  def preludes(hir) = hir.body.is_a?(Zr::Hir::Seq) ? hir.body.stmts.grep(Zr::Hir::Require).map(&:feature) : []
end
