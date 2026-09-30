# frozen_string_literal: true
# zr-test: eval

require "test_helper"
require_relative "../../lib/zr/runtime"

# Tests which programs include eval support.
#
# A program that compiles ruby code while it runs links in eval support
# (the compiled compiler). That adds 44 MB to the binary and a minute to
# the build. Thus the loader's `evals?` must be exact. If it is too
# narrow, a program cannot compile the code it must. If it is too wide,
# each user of a common library pays for a compiler that it never calls.
class EvalDetectionTest < Minitest::Test
  def test_eval_of_a_string_includes_eval_support
    assert carried?(%(eval("1 + 1")\n))
    assert carried?(%(class K; end\nK.class_eval("def a = 1")\n))
    assert carried?(%(v = "1"\n1.instance_eval(v)\n))
  end

  def test_eval_of_a_block_does_not_include_eval_support
    refute carried?(%(class K; end\nK.class_eval { def a = 1 }\n))
    refute carried?(%(1.instance_eval { self }\n))
  end

  # `require` of a feature that is in the runtime loads no file.
  # `autoload` of such a feature registers nothing: ruby returns nil for
  # `Object.autoload?(:Set)` after `autoload :Set, "set"`. Neither one
  # needs eval support.
  def test_builtin_feature_does_not_include_eval_support
    refute carried?(%(require "set"\np Set[1]\n))
    refute carried?(%(autoload :Set, "set"\np Set[1]\n))
  end

  def test_autoload_of_a_file_does_not_include_eval_support
    refute carried?(%(autoload :URI, "uri"\np URI.name\n))
  end

  # These cases still need eval support. `fileutils` defines methods
  # with an eval of a heredoc that interpolates computed names,
  # for example `names.each { |name| module_eval("def #{name}...") }`.
  # Thus the compiler cannot read the string at build time. Of the 36
  # heredoc evals in the vendored stdlib, 31 interpolate. Thus
  # `require "fileutils"` adds 44 MB to a program. json evals nothing:
  # its receiverless `load` is JSON's own method.
  def test_heredoc_eval_includes_eval_support
    assert carried?(%(class K; end\nK.class_eval <<~R\n  def a = 1\nR\n))
    assert carried?(%(require "fileutils"\np FileUtils.respond_to?(:mkdir_p)\n))
    refute carried?(%(require "json"\np JSON.name\n))
  end

  # Each `using` fills an entry in one refinement table for the whole
  # program, and the compiler gives each entry its id. Eval support has
  # its own `using` statements (the prism port uses one) and loads on
  # the first eval. If the program also started its ids at zero, eval
  # support would overwrite them. Thus program ids start after the ids
  # of eval support, as symbol ids and site indices do.
  def test_refinement_ids_start_after_eval_support_ids
    support = Zr.eval_support(Zr::Target.default)
    assert_operator support.activations, :>, 0, "eval support activates refinements of its own"

    loader = Zr::Hir::Build::Loader.new(Zr::Hir::Build.stdlib(Zr::Target.default), external: support)
    assert_equal support.activations, loader.activations

    Dir.mktmpdir("zr-eval-") do |work|
      rb = File.join(work, "using.rb")
      source = "module M; refine Integer do; def trip = self * 3; end; end\nusing M\np 7.trip\n"
      File.write(rb, source)
      loader.unit(rb, source)
    end
    assert_equal support.activations + 1, loader.activations
  end

  private

  # Returns true if the program in `source` links in eval support.
  def carried?(source)
    Dir.mktmpdir("zr-eval-") do |work|
      rb = File.join(work, "eval_probe.rb")
      File.write(rb, source)
      loader = Zr::Hir::Build::Loader.new(Zr::Hir::Build.stdlib(Zr::Target.default))
      loader.unit(rb, source)
      loader.evals?
    end
  end
end
