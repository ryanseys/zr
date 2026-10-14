# frozen_string_literal: true

require "test_helper"
require "open3"
require_relative "../../tool/lib/zr/dev/fuzz"

# Tests the program generator of `zr-dev fuzz`: a seed gives the same
# bytes, every program parses, a pack that is off writes nothing, and a
# program runs on ruby within its limit and gives the same output twice
# (tool/lib/zr/dev/fuzz/gen/).
class FuzzGenTest < Minitest::Test
  Gen = Zr::Dev::Fuzz::Gen

  def test_the_same_seed_gives_the_same_program
    assert_equal Gen.program(17).first, Gen.program(17).first
    refute_equal Gen.program(17).first, Gen.program(18).first
  end

  def test_every_program_parses
    300.times do |seed|
      source, = Gen.program(seed)

      assert_empty Prism.parse(source).errors, "seed #{seed}"
    end
  end

  def test_a_pack_that_is_off_writes_nothing
    20.times do |seed|
      source, swarm = Gen.program(seed, only: %w[values control])

      assert_equal %w[values control], swarm.packs
      refute_match(/Fiber|Ractor|class C\d|FuzzError|eval\(|require /, source, "seed #{seed}")
    end
  end

  def test_the_core_packs_are_always_on
    50.times do |seed|
      _, swarm = Gen.program(seed)

      assert swarm.on?("values") && swarm.on?("control"), "seed #{seed}"
    end
  end

  def test_each_unit_uses_only_locals_that_it_defines
    40.times do |seed|
      source, = Gen.program(seed, only: %w[values control])
      tree = Prism.parse(source).value
      reads = []
      Zr::Dev::Fuzz::Reducer.walk(tree) { |n| reads << n if n.is_a?(Prism::CallNode) && n.variable_call? }

      assert_empty reads.map(&:name).grep(/\A[a-z]+\d+\z/), "seed #{seed}: a generated name read as a method call"
    end
  end

  def test_a_snippet_stands_alone
    20.times { |seed| assert_empty Prism.parse(Gen.snippet(seed)).errors, "seed #{seed}" }
  end

  def test_the_catalog_names_methods_that_ruby_has
    Gen::Catalog::CLASSES.each do |type, klass|
      names = Gen::Catalog.names(type)

      refute_empty names
      names.each do |name|
        assert klass.public_method_defined?(name), "#{klass}##{name}"
        assert_includes 0..4, Gen::Catalog.arg_count(type, name, Random.new(1))
      end
      assert_empty names & Gen::Catalog::BLOCKED
    end
  end

  def test_programs_run_on_ruby_in_time_and_give_the_same_output_twice
    6.times do |seed|
      source, = Gen.program(seed * 101)
      one = run_ruby(source)
      two = run_ruby(source)

      assert_equal one, two, "seed #{seed * 101}"
      assert_match(/u1[.:]/, one.first, "seed #{seed * 101}: #{one[1][0, 400]}")
    end
  end

  def run_ruby(source)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "prog.rb"), source)
      out, err, status = Open3.capture3(Zr::Harness::CleanEnv.env(Zr::Harness::Reference.env), RbConfig.ruby, "prog.rb",
                                        chdir: dir, unsetenv_others: true)
      # Object addresses change from run to run; the oracle hides them too.
      [Zr::Diff.unaddressed(out), Zr::Diff.unaddressed(err), status.exitstatus]
    end
  end
end
