# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/program"

# `Program.gem_redirects` reads eval support's files only for a program
# that loads a file from a gem: eval support's list of files comes from
# its lowering, which an empty cache would make for a program with no
# eval. test/unit/gem_redirect_test.rb runs the redirects themselves.
class GemRedirectsTest < Minitest::Test
  Unit = Struct.new(:file)
  Hir = Struct.new(:units)
  Gem = Struct.new(:root) do
    def root_of(path) = path.start_with?("#{root}/") ? root : nil
  end
  GemSet = Struct.new(:gems)

  # Eval support whose files a test gives; nil raises, as a read that
  # would lower it.
  class Support
    def initialize(units) = @units = units

    def units = @units || raise("read eval support's files")
  end

  STDLIB = Zr::Library::Roots.stdlib(Zr::Target::AARCH64_DARWIN).first

  def test_a_program_with_no_file_of_a_gem_reads_no_eval_support
    hir = Hir.new([Unit.new("/app/main.rb"), Unit.new(nil)])
    gems = GemSet.new([Gem.new("/gems/json-9")])

    assert_equal({}, redirects(hir, Support.new(nil), gems))
  end

  def test_a_gems_file_that_eval_support_carries_runs_in_place_of_the_copy
    copy = File.join(STDLIB, "json/common.rb")
    hir = Hir.new([Unit.new("/app/main.rb"), Unit.new("/gems/json-9/json/common.rb")])
    gems = GemSet.new([Gem.new("/gems/json-9")])

    assert_equal({ copy => "/gems/json-9/json/common.rb" }, redirects(hir, Support.new({ copy => "zr_u1" }), gems))
  end

  private

  def redirects(hir, support, gems) = Zr::Program.send(:gem_redirects, hir, support, gems, Zr::Target::AARCH64_DARWIN)
end
