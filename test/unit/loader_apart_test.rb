# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/hir"

# A loader with `apart` leaves for run time a require inside a method of one
# bundled gem that finds another bundled gem: eval support carries irb, and
# irb loads rdoc only when its document dialog runs.
class LoaderApartTest < Minitest::Test
  Roots = Zr::Library::Roots

  def test_a_file_of_one_bundled_gem_requiring_another_waits
    assert loader(apart: true).apart?(file("irb", "irb/input-method.rb"), file("rdoc", "rdoc.rb"))
  end

  def test_a_file_of_a_gem_requiring_its_own_files_does_not_wait
    refute loader(apart: true).apart?(file("irb", "irb/debug.rb"), file("irb", "irb/debug/ui.rb"))
  end

  def test_a_require_of_the_standard_library_does_not_wait
    refute loader(apart: true).apart?(file("irb", "irb/pager.rb"), File.join(Roots.pure, "shellwords.rb"))
  end

  def test_a_file_outside_the_bundled_gems_does_not_wait
    refute loader(apart: true).apart?("/app/main.rb", file("rdoc", "rdoc.rb"))
  end

  def test_a_loader_without_apart_never_waits
    refute loader(apart: false).apart?(file("irb", "irb/input-method.rb"), file("rdoc", "rdoc.rb"))
  end

  private

  def loader(apart:) = Zr::Hir::Build::Loader.new([], apart: apart)

  def file(gem, path) = File.join(Roots.lib_of(gem), path)
end
