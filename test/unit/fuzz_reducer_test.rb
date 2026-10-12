# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/lib/zr/dev/fuzz"
require_relative "../../tool/lib/zr/dev/fuzz/reducer"

# Tests the reducer of `zr-dev fuzz` with a predicate in place of ruby
# and zr: it must find the smallest program that keeps the failure,
# check only programs that parse, and never check one program twice
# (tool/lib/zr/dev/fuzz/reducer.rb).
class FuzzReducerTest < Minitest::Test
  Fuzz = Zr::Dev::Fuzz

  SOURCE = <<~RUBY
    # a note
    a = 1 # the first

    b = 2
    def foo(x, y)
      puts x
      raise Foo if y
    end
    c = [1, 2, 3]
    foo(a, b)
  RUBY

  def failing = verdict("output-diff", "k")
  def passing = verdict("same", "")

  def verdict(kind, key)
    Fuzz::Oracle::Result.new(verdict: Fuzz::Verdict.new(kind: kind, key: key, detail: ""))
  end

  # A reducer whose check fails a program that names both `raise` and
  # `Foo`, and that records each program it checks.
  def reducer(seen, budget: 400)
    check = lambda do |source|
      seen << source
      source.include?("raise") && source.include?("Foo") ? failing : passing
    end
    Fuzz::Reducer.new(check: check, jobs: 2, budget: budget)
  end

  def test_reduce_keeps_only_what_the_failure_needs
    seen = Queue.new
    source, result, = reducer(seen).reduce(SOURCE, failing)

    assert_equal "raise Foo\n", source
    assert_equal "output-diff", result.verdict.kind
  end

  def test_reduce_checks_only_programs_that_parse_and_each_once
    seen = Queue.new
    reducer(seen).reduce(SOURCE, failing)
    checked = Array.new(seen.size) { seen.pop }

    assert(checked.all? { |source| Prism.parse(source).errors.empty? })
    assert_equal checked.uniq.size, checked.size
  end

  def test_reduce_stops_at_its_budget
    seen = Queue.new
    reducer(seen, budget: 3).reduce(SOURCE, failing)

    assert_operator seen.size, :<=, 3 + 1
  end

  def test_reduce_of_a_program_that_does_not_parse_removes_lines
    seen = Queue.new
    junk = "p 1\nraise Foo\ndef (\np 2\n"
    source, = reducer(seen).reduce(junk, failing)

    assert_equal "raise Foo\n", source
  end

  def test_reduce_does_not_try_a_timeout
    seen = Queue.new
    slow = verdict("timeout", "")
    source, = reducer(seen).reduce(SOURCE, slow)

    assert_equal SOURCE, source
    assert_equal 0, seen.size
  end

  def test_shape_lists_node_kinds_and_method_names
    shape = Fuzz::Reducer.shape("x = [1].map { _1 + 2 }\n")

    assert_includes shape.split, "Array"
    assert_includes shape.split, ".map"
    assert_includes shape.split, ".+"
    assert_nil Fuzz::Reducer.shape("def (")
  end
end
