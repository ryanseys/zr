# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../tool/lib/zr/dev/fuzz"

# Tests how `zr-dev fuzz` tells where a fault is, from ruby's answer, the
# binary's and the hosted run's (Oracle#layer, tool/lib/zr/dev/fuzz/oracle.rb).
class FuzzOracleTest < Minitest::Test
  Fuzz = Zr::Dev::Fuzz

  def answer(out) = Zr::Harness::Answer.new(out.b, "".b, 0, nil)

  def build(status) = Fuzz::BuilderClient::Build.new(status: status, signal: nil, timeout: false, stderr: "".b, seconds: 0, lines: [])

  # The layer of a failure where ruby prints "1" and zr "2", when the
  # hosted run prints `hosted`.
  def layer(hosted, status: 0)
    Dir.mktmpdir do |dir|
      oracle = Fuzz::Oracle.new(builder: nil, work: dir)
      oracle.define_singleton_method(:hosted) { |_source, _pin| hosted }
      result = Fuzz::Oracle::Result.new(verdict: Fuzz::Verdict.new(kind: "output-diff", key: "", detail: ""),
                                        ruby: answer("1\n"), zr: status.zero? ? answer("2\n") : nil, build: build(status))
      oracle.layer("p 1", result, "/pin")
    end
  end

  def test_layer_is_kernel_when_the_hosted_run_gives_the_binarys_answer
    assert_equal "kernel", layer(answer("2\n"))
  end

  def test_layer_is_compiler_when_the_hosted_run_gives_rubys_answer
    assert_equal "compiler", layer(answer("1\n"))
  end

  def test_layer_is_compiler_when_the_build_failed
    assert_equal "compiler", layer(nil, status: 3)
  end

  def test_layer_is_mixed_when_all_three_differ_and_host_error_when_the_host_stops
    assert_equal "mixed", layer(answer("3\n"))
    assert_equal "host-error", layer(Zr::Harness::Answer.new("".b, "".b, :timeout, nil))
  end
end
