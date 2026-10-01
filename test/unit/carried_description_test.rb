# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require "zr/runtime"
require "zr/hir/loader"

# Eval support carries the kernel's description as a Ruby file. No file
# on disk has it: `require "zr_description"` finds a fixed name, and the
# loader takes the source from the runtime's own description. So a
# compiler that zr builds does not carry where its cache was.
class CarriedDescriptionTest < Minitest::Test
  def test_the_carried_text_is_the_runtimes_description
    runtime = Zr::Runtime.for(Zr::Target.default)

    assert_equal Zr::Machine::Description.carried(runtime.send(:cached).fetch(:description)), runtime.carried_text
  end

  def test_the_loader_resolves_zr_description_to_its_fixed_name
    loader = Zr::Hir::Build::Loader.new([], description: -> { "Zr = 1\n" })

    assert_equal Zr::Library::Roots::DESCRIPTION, loader.resolve(:require, "zr_description", "/app/a.rb")
    assert_nil Zr::Hir::Build::Loader.new([]).resolve(:require, "zr_description", "/app/a.rb")
    assert Zr::Library::Roots.runtime_file?(Zr::Library::Roots::DESCRIPTION), "the loader treats it as the runtime's own"
  end
end
