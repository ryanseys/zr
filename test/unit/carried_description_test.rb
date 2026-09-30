# frozen_string_literal: true

require "test_helper"
require "zr/runtime"
require "zr/hir/loader"

# Eval support carries the kernel's description as a Ruby file. A build
# writes it into the store from the runtime's own description, keyed by
# its bytes, and `require "zr_description"` finds it there.
class CarriedDescriptionTest < Minitest::Test
  def setup
    @runtime = Zr.runtime(Zr::Target.default)
  end

  def test_the_carried_file_is_the_runtimes_description_in_the_store
    path = @runtime.carry_description!

    assert_equal Zr::Machine::Description.carried(@runtime.send(:cached).fetch(:description)), File.binread(path)
    assert path.start_with?(File.join(Zr::Store.dir, "description", "")), path
    assert Zr::Hir::Build.runtime_file?(path), "the loader treats it as the runtime's own"
  end

  def test_a_second_carry_leaves_the_file_as_it_is
    path = @runtime.carry_description!
    before = File.mtime(path)

    assert_equal path, @runtime.carry_description!
    assert_equal before, File.mtime(path)
  end

  def test_the_loader_resolves_zr_description_to_the_carried_file
    loader = Zr::Hir::Build::Loader.new([], description: -> { "/store/description/ab/abcd/zr_description.rb" })

    assert_equal "/store/description/ab/abcd/zr_description.rb", loader.resolve(:require, "zr_description", "/app/a.rb")
    assert_nil Zr::Hir::Build::Loader.new([]).resolve(:require, "zr_description", "/app/a.rb")
  end
end
