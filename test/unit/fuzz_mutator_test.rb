# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/lib/zr/dev/fuzz"

# Tests the mutator of `zr-dev fuzz`: each edit gives a program that
# parses, a seed gives the same edits each time, and each kind of edit
# changes what it names (tool/lib/zr/dev/fuzz/mutator.rb).
class FuzzMutatorTest < Minitest::Test
  Fuzz = Zr::Dev::Fuzz

  SOURCE = <<~RUBY
    a = 10
    b = 3
    s = "text"
    def f(x, y) = x + y
    p f(a, b)
    p a < b, a * b
    p s, :sym, 2.5, true
    [1, 2].each { |i| p i - a }
  RUBY

  OTHER = "q = [7, 8].map { _1 * 2 }\np q\n"

  def mutator = Fuzz::Mutator.new(seeds: ->(_) { OTHER }, generator: ->(_) { "p :inserted" })

  def test_every_result_parses
    200.times do |seed|
      out, = mutator.mutate(SOURCE, Random.new(seed))

      assert_empty Prism.parse(out).errors, "seed #{seed}:\n#{out}" if out
    end
  end

  def test_the_same_seed_gives_the_same_program
    one = mutator.mutate(SOURCE, Random.new(42))
    two = mutator.mutate(SOURCE, Random.new(42))

    assert_equal one, two
  end

  def test_each_kind_of_edit_happens_and_changes_the_program
    seen = Hash.new(0)
    300.times do |seed|
      out, kinds = mutator.mutate(SOURCE, Random.new(seed), count: 1)
      next unless out

      refute_equal SOURCE, out
      kinds.each { seen[_1] += 1 }
    end

    assert_equal Fuzz::Mutator::KINDS.uniq.sort, seen.keys.sort
  end

  def test_an_operator_stays_in_its_group
    rng = Random.new(1)
    20.times do
      out = mutator.send(:operator, SOURCE, Prism.parse(SOURCE).value, rng) or next
      changed = out.lines.zip(SOURCE.lines).find { |a, b| a != b }.first

      assert_match(/a (<|<=|>|>=|==|!=|<=>) b|x [-*\/%] y|a [+\/%-] b|i [+*\/%] a/, changed)
    end
  end

  def test_input_reads_another_local_of_the_same_scope
    rng = Random.new(3)
    outs = Array.new(30) { mutator.send(:input, SOURCE, Prism.parse(SOURCE).value, rng) }.compact

    refute_empty outs
    outs.each { |out| assert_empty Prism.parse(out).errors }
  end

  def test_a_program_that_does_not_parse_gets_no_edit
    assert_nil mutator.mutate("def (", Random.new(1))
  end
end
