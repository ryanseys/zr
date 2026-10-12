# frozen_string_literal: true

require "test_helper"
require_relative "../../tool/lib/zr/dev/fuzz"

# Tests how `zr-dev fuzz` names a difference between ruby and zr: the
# kind, the key that leaves out what changes from case to case, the
# bucket, and the known differences (tool/lib/zr/dev/fuzz/verdict.rb,
# known.rb).
class FuzzVerdictTest < Minitest::Test
  Answer = Zr::Harness::Answer
  Build = Zr::Dev::Fuzz::BuilderClient::Build
  Classify = Zr::Dev::Fuzz::Classify

  def answer(out = "", err = "", code = 0, signal = nil) = Answer.new(out.b, err.b, code, signal) # rubocop:disable Metrics/ParameterLists

  def built = Build.new(status: 0, signal: nil, timeout: false, stderr: "".b, seconds: 0.1, lines: [])

  def failed(stderr, status: 1, signal: nil, timeout: false)
    Build.new(status: status, signal: signal, timeout: timeout, stderr: stderr.b, seconds: 0.1, lines: [])
  end

  def test_verdict_same_answers_is_same
    verdict = Classify.verdict(answer("1\n"), built, answer("1\n"))

    assert_predicate verdict, :same?
  end

  def test_verdict_refusal_names_the_form
    err = "zr: prog.rb:3:5: zr does not support flip-flop (FlipFlop) yet\n"
    verdict = Classify.verdict(answer, failed(err, status: 3), nil)

    assert_equal "refused", verdict.kind
    assert_equal "flip-flop (FlipFlop)", verdict.key
  end

  def test_verdict_internal_error_keys_on_class_and_frames_without_lines
    err = "zr: internal error: NoMethodError: undefined method 'x' for nil\n" \
          "\tfrom zr/lower/function/sends.rb:120:in 'Zr::Lower::Sends#send_call'\n" \
          "\tfrom zr/lower/function.rb:88:in 'Zr::Lower::Function#lower'\n"
    other = err.gsub("120", "121").gsub("88", "90")
    one = Classify.verdict(answer, failed(err), nil)
    two = Classify.verdict(answer, failed(other), nil)

    assert_equal "internal-error", one.kind
    assert_includes one.key, "zr/lower/function/sends.rb#Zr::Lower::Sends#send_call"
    assert_equal one.bucket, two.bucket
  end

  def test_verdict_backend_refusal_and_build_crash
    backend = Classify.verdict(answer, failed("zr: zr cannot compile this program: too many registers: 300. This is a limit"), nil)
    crash = Classify.verdict(answer, failed("", status: nil, signal: 11), nil)
    slow = Classify.verdict(answer, failed("", status: nil, timeout: true), nil)

    assert_equal %w[backend-refused build-crash build-timeout], [backend.kind, crash.kind, slow.kind]
    assert_equal "too many registers", backend.key
  end

  def test_verdict_run_kinds
    ruby = answer("ok\n")

    assert_equal "timeout", Classify.verdict(ruby, built, answer("", "", :timeout)).kind
    assert_equal "memory", Classify.verdict(ruby, built, answer("", "", :memory)).kind
    assert_equal "crash", Classify.verdict(ruby, built, answer("", "", nil, 11)).kind
    assert_equal "bug", Classify.verdict(ruby, built, answer("", "[BUG] heap corrupt at 12\n", nil, 6)).kind
    assert_equal "status-diff", Classify.verdict(ruby, built, answer("ok\n", "", 1)).kind
    assert_equal "output-diff", Classify.verdict(ruby, built, answer("no\n")).kind
  end

  def test_verdict_unimplemented_names_the_method
    zr = answer("", "prog.rb:1:in 'x': Integer#foo is not implemented yet (NotImplementedError)\n", 1)
    verdict = Classify.verdict(answer("1\n"), built, zr)

    assert_equal "unimplemented", verdict.kind
    assert_equal "Integer#foo is not implemented yet", verdict.key
  end

  def test_verdict_exception_diff_keys_on_class_and_message_pattern
    ruby = answer("", "prog.rb:4:in 'f': divided by 0 (ZeroDivisionError)\n", 1)
    zr = answer("", "prog.rb:5:in 'f': undefined method 'x' (NoMethodError)\n", 1)
    verdict = Classify.verdict(ruby, built, zr)

    assert_equal "exception-diff", verdict.kind
    assert_equal "ZeroDivisionError: divided by N | NoMethodError: undefined method 'Q'", verdict.key
  end

  def test_template_drops_numbers_quotes_and_addresses
    assert_equal "uN: \"Q\" #<Foo:ADDR> N", Classify.template(%(u12: "abc" #<Foo:0x000000010a2b3c4d> -3.5e10))
  end

  def test_bucket_changes_with_the_shape
    verdict = Zr::Dev::Fuzz::Verdict.new(kind: "output-diff", key: "N | N", detail: "")

    refute_equal verdict.bucket, verdict.bucket("CallNode Integer#pow")
    assert_match(/\Aoutput-diff-\h{10}\z/, verdict.bucket)
  end

  def test_known_matches_the_verdict_not_the_program
    disasm = Zr::Dev::Fuzz::Verdict.new(kind: "unimplemented", key: "RubyVM::InstructionSequence#disasm is not implemented yet",
                                        detail: "")
    plain = Zr::Dev::Fuzz::Verdict.new(kind: "output-diff", key: "true | false", detail: "ruby \"true\", zr \"false\"")

    assert_match(/YARV/, Zr::Dev::Fuzz::Known.reason(disasm))
    assert_nil Zr::Dev::Fuzz::Known.reason(plain)
  end
end
