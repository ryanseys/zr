# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/lib/zr/dev/fuzz"

# Tests the rewrites of `zr-dev fuzz --mode meta` and the junk of `--mode
# junk`: a rewrite parses and leaves patterns alone, and junk counts only
# as a fault of zr's build or of its SyntaxError report
# (tool/lib/zr/dev/fuzz/metamorphic.rb, junk.rb, triage.rb).
class FuzzMetamorphicTest < Minitest::Test
  Fuzz = Zr::Dev::Fuzz

  SOURCE = <<~RUBY
    x = 3
    p [x, 1.5, "s", nil]
    case [1, 2]
    in [1, Integer => b] then p b
    end
    p defined?(1)
    puts "\#{x} items"
  RUBY

  def test_every_rewrite_parses
    100.times do |seed|
      out, kinds = Fuzz::Metamorphic.transform(SOURCE, Random.new(seed), generator: ->(_) { "p :dead" })
      next unless out

      assert_empty Prism.parse(out).errors, "seed #{seed} #{kinds}:\n#{out}"
      assert out.start_with?("def __opaque(x) = x\n")
    end
  end

  def test_opaque_leaves_patterns_defined_and_strings_parts_alone
    50.times do |seed|
      out = Fuzz::Metamorphic.opaque(SOURCE, Prism.parse(SOURCE).value, Random.new(seed)) or next

      assert_includes out, "in [1, Integer => b]"
      assert_includes out, "defined?(1)"
      assert_includes out, "\#{x} items"
    end
  end

  def test_wrap_moves_only_statements_that_stand_alone
    tree = Prism.parse("y = 1\np y\nreturn if y\n[1].each { |i| break }\n").value
    movable = Fuzz::Metamorphic.statements(tree).select { Fuzz::Metamorphic.movable?(_1) }

    assert_equal ["p y"], movable.map(&:slice)
  end

  def test_junk_changes_the_source
    changed = Array.new(30) { |seed| Fuzz::Junk.break_up(SOURCE, Random.new(seed)) }

    assert(changed.all? { _1 != SOURCE })
  end

  def test_junk_counts_only_build_faults_and_syntax_reports
    answer = ->(err) { Zr::Harness::Answer.new("".b, err.b, 1, nil) }
    result = lambda do |kind, ruby_err|
      Fuzz::Oracle::Result.new(verdict: Fuzz::Verdict.new(kind: kind, key: "", detail: ""), ruby: answer.call(ruby_err))
    end

    assert Fuzz::Triage.junk_fault?(result.call("internal-error", ""))
    assert Fuzz::Triage.junk_fault?(result.call("exception-diff", "prog.rb:1: syntax errors found (SyntaxError)"))
    refute Fuzz::Triage.junk_fault?(result.call("refused", "prog.rb: syntax error"))
    refute Fuzz::Triage.junk_fault?(result.call("output-diff", ""))
  end
end
