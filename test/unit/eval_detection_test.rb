# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"

# Which programs carry the compiler.
#
# A program that compiles ruby while it runs is linked beside the eval
# road -- the compiler, compiled -- which is 44 MB of the binary and a
# minute of the build. So the question the loader answers, `evals?`, is
# worth being exact about: too narrow an answer is a program that cannot
# compile what it must, and too wide is every user of a common library
# paying for a compiler it never calls.
class EvalRoadTest < Minitest::Test
  def test_a_string_the_program_compiles_carries_it
    assert carried?(%(eval("1 + 1")\n))
    assert carried?(%(class K; end\nK.class_eval("def a = 1")\n))
    assert carried?(%(v = "1"\n1.instance_eval(v)\n))
  end

  def test_a_block_is_not_a_string
    refute carried?(%(class K; end\nK.class_eval { def a = 1 }\n))
    refute carried?(%(1.instance_eval { self }\n))
  end

  # `require` of a feature the runtime already holds loads no file, and
  # `autoload` of one registers nothing: ruby answers nil for
  # `Object.autoload?(:Set)` after `autoload :Set, "set"`. Neither needs
  # a compiler, and a library that writes the second used to hand one to
  # every program that required it.
  def test_a_feature_the_runtime_already_holds_carries_nothing
    refute carried?(%(require "set"\np Set[1]\n))
    refute carried?(%(autoload :Set, "set"\np Set[1]\n))
  end

  def test_a_feature_that_resolves_to_a_file_carries_nothing_either
    refute carried?(%(autoload :URI, "uri"\np URI.name\n))
  end

  # What is left, and why it stays. `fileutils` and `json` define their
  # methods by evaluating a heredoc, and the heredoc is built from names
  # the program computes -- `names.each { |name| module_eval("def
  # #{name}...") }` -- so there is no string for the compiler to read
  # where it stands. Of the 36 heredoc evals in the vendored stdlib, 31
  # interpolate. These libraries want a compiler because they write their
  # own methods while they run, and `require "fileutils"` costs a
  # program 44 MB for it.
  def test_a_library_that_evaluates_a_literal_string_still_carries_it
    assert carried?(%(class K; end\nK.class_eval <<~R\n  def a = 1\nR\n))
    assert carried?(%(require "fileutils"\np FileUtils.respond_to?(:mkdir_p)\n))
    assert carried?(%(require "json"\np JSON.name\n))
  end

  # A `using` fills a row of one table the whole program shares, and it
  # is the compiler that numbers the rows. The road holds `using`
  # statements of its own -- the prism port reaches its node writers
  # through one -- and it loads on the first eval, so a program that
  # numbered its rows from zero as well would have the road take them
  # back the moment it compiled anything. The rows go on from the
  # road's, as the symbol ids and the site indices already do.
  def test_a_program_numbers_its_using_rows_past_the_roads
    road = Zr.eval_support(Zr::Target.default)
    assert_operator road.activations, :>, 0, "the road activates refinements of its own"

    loader = Zr::Hir::Build::Loader.new(Zr::Hir::Build.stdlib(Zr::Target.default), external: road)
    assert_equal road.activations, loader.activations

    Dir.mktmpdir("zr-road-") do |work|
      rb = File.join(work, "using.rb")
      source = "module M; refine Integer do; def trip = self * 3; end; end\nusing M\np 7.trip\n"
      File.write(rb, source)
      loader.unit(rb, source)
    end
    assert_equal road.activations + 1, loader.activations
  end

  private

  # Whether the program in `source` would be linked beside the compiler.
  def carried?(source)
    Dir.mktmpdir("zr-road-") do |work|
      rb = File.join(work, "road.rb")
      File.write(rb, source)
      loader = Zr::Hir::Build::Loader.new(Zr::Hir::Build.stdlib(Zr::Target.default))
      loader.unit(rb, source)
      loader.evals?
    end
  end
end
