# frozen_string_literal: true

# Does a generated spec file still say what the corpus cases said?
#
#   ruby tools/convert_verify.rb <spec file> <case path>...
#
# The spec is loaded against a stand-in `ze0` that answers nothing and
# only records what it was handed, so nothing is compiled and nothing is
# run. Each example's program and each expectation are then held to the
# case they came from: same source bytes, same recorded answer, same
# arguments. A difference names the example. This is what says a
# conversion lost nothing, and it costs a second for a whole area.

require_relative "../test/support/harness/case"

# What a guard asks of the machine. The real ones live in
# `test/support/spec.rb`, which loads the whole compiler; a verifier
# that compiles nothing answers them itself.
module Ze0
  module Spec
    def self.platform = "macos"
    def self.need?(_name) = true
  end
end

module ConvertVerify
  ROOT = File.expand_path("..", __dir__)

  Seen = Struct.new(:name, :source, :kwargs, :want, keyword_init: true)

  # The world a spec file is loaded into: `describe`/`it` collect, `ze0`
  # records, `_(x).must_equal y` records, and nothing else happens.
  class Sandbox
    attr_reader :seen

    def initialize = @seen = []

    def describe(_name, &block) = instance_eval(&block)

    def it(name, &block)
      @current = Seen.new(name: name, want: {})
      @seen << @current
      instance_eval(&block)
    rescue StandardError => e
      @current.want[:error] = e
    end

    def ze0(source, **kwargs)
      @current.source = source
      @current.kwargs = kwargs
      Recorder.new(@current, :result)
    end

    # `_(result.stdout)` hands back the stream the chain already named;
    # `_(ze0(...).stdout)` is the same chain written in one line.
    def _(value) = value.is_a?(Recorder) ? value : Recorder.new(@current, value)

    def skip(_why = nil) = nil

    # `_(result.stdout).must_equal "AB\n"` lands here: the left side says
    # which stream, the right side is what ruby recorded.
    class Recorder
      def initialize(example, value)
        @example = example
        @value = value
      end

      def stdout = Recorder.new(@example, :stdout)
      def stderr = Recorder.new(@example, :stderr)
      def status = Recorder.new(@example, :status)
      def signal = Recorder.new(@example, :signal)

      def must_equal(want)
        @example.want[@value] = want
        want
      end
    end
  end

  module_function

  def load(path)
    box = Sandbox.new
    box.instance_eval(File.read(path).sub(/^require "spec_helper"$/, ""), path)
    box.seen
  end

  # Every way an example may part from its case.
  def differences(seen, kase, rb)
    rel = rb.delete_prefix("#{ROOT}/")
    out = []
    d = kase.directives
    dir = File.dirname(rb)
    want = Ze0::Harness::Answer.new(Ze0::Harness::Normalize.bytes(kase.answer.stdout, rb, dir),
                                    Ze0::Harness::Normalize.bytes(kase.answer.stderr, rb, dir),
                                    kase.answer.code, kase.answer.signal)
    program = kase.program.each_line.reject { |l| l.start_with?("#@") }.join.force_encoding(Encoding::UTF_8)

    if seen.kwargs.nil?
      why = seen.want[:error]
      return ["#{rel}: the example never called ze0#{why ? " (#{why.class}: #{why.message})" : ""}"]
    end

    out << "program: #{apart(program, seen.source)}" unless seen.source == program
    out << "stdout: #{apart(text(want.stdout), seen.want[:stdout])}" unless same?(want.stdout, seen.want[:stdout])
    unless same?(want.stderr, seen.want.fetch(:stderr, ""))
      out << "stderr: #{apart(text(want.stderr), seen.want[:stderr])}"
    end
    code = seen.want.fetch(:status, 0)
    out << "status: recorded #{want.code}, spec #{code}" unless (want.code || 0) == code
    signal = seen.want[:signal]
    out << "signal: recorded #{want.signal}, spec #{signal}" unless want.signal == signal
    out << "argv: recorded #{d.args.inspect}, spec #{seen.kwargs.fetch(:argv, []).inspect}" unless d.args == seen.kwargs.fetch(:argv, [])
    env = d.env.merge(d.zeo_env)
    out << "env: recorded #{env.inspect}, spec #{seen.kwargs.fetch(:env, {}).inspect}" unless env == seen.kwargs.fetch(:env, {})
    out.map { |why| "#{rel}: #{why}" }
  end

  def text(bytes)
    out = bytes.dup.force_encoding(Encoding::UTF_8)
    out.valid_encoding? ? out : bytes
  end

  def same?(recorded, spec) = !spec.nil? && text(recorded) == spec

  # Where two strings part, in a line a terminal holds.
  def apart(want, got)
    return "spec asserts nothing" if got.nil?

    n = want.lines.zip(got.lines).index { |a, b| a != b } || 0
    "line #{n + 1}: recorded #{want.lines[n].inspect}, spec #{got.lines[n].inspect}"
  end
end

spec, *cases = ARGV
abort "usage: ruby tools/convert_verify.rb <spec file> <case path>..." unless spec && !cases.empty?

cases = cases.flat_map { |a| File.directory?(a) ? Dir[File.join(a, "*.rb")].sort : [a] }
seen = ConvertVerify.load(spec)
by_name = seen.to_h { |s| [s.name, s] }

differences = []
checked = 0
cases.each do |rb|
  rb = File.expand_path(rb)
  kase = Ze0::Harness::Case.read(rb)
  next unless kase.recorded?

  name = File.basename(rb, ".rb").tr("_", " ")
  example = by_name[name]
  next unless example # refused by the converter; `--plan` names those

  checked += 1
  differences.concat(ConvertVerify.differences(example, kase, rb))
end

differences.each { |why| warn why }
extra = by_name.keys - cases.map { |rb| File.basename(rb, ".rb").tr("_", " ") }
extra.each { |name| warn "#{spec}: #{name.inspect} matches no case" }
puts "#{checked} example(s) checked, #{differences.size + extra.size} difference(s)"
exit(differences.empty? && extra.empty? ? 0 : 1)
