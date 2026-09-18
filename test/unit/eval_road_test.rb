# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/zr"

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

  # What is left, and what it costs. `fileutils` and `json` define their
  # methods by evaluating a heredoc: a literal string, in a scope written
  # directly above it, which the compiler could read where it stands
  # instead of carrying itself into the binary to read it later. Until it
  # does, `require "fileutils"` hands 44 MB of compiler to a program that
  # only wanted `mkdir_p`.
  def test_a_library_that_evaluates_a_literal_string_still_carries_it
    assert carried?(%(class K; end\nK.class_eval <<~R\n  def a = 1\nR\n))
    assert carried?(%(require "fileutils"\np FileUtils.respond_to?(:mkdir_p)\n))
    assert carried?(%(require "json"\np JSON.name\n))
  end

  private

  # Whether the program in `source` would be linked beside the compiler.
  def carried?(source)
    Dir.mktmpdir("ze0-road-") do |work|
      rb = File.join(work, "road.rb")
      File.write(rb, source)
      loader = Ze0::Hir::Build::Loader.new(Ze0::Hir::Build.stdlib(Ze0::Target.default))
      loader.unit(rb, source)
      loader.evals?
    end
  end
end
