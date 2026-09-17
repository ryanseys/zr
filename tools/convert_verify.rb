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
require_relative "subjects"
require_relative "convert"
require_relative "../test/support/reader"

module ConvertVerify
  ROOT = File.expand_path("..", __dir__)

  Seen = Ze0::Reader::Example

  module_function

  def load(path) = Ze0::Reader.read(path)

  # Every way an example may part from its case.
  def differences(seen, kase, rb)
    rel = rb.delete_prefix("#{ROOT}/")
    out = []
    d = kase.directives
    dir = File.dirname(rb)
    want = Ze0::Harness::Answer.new(Ze0::Harness::Normalize.bytes(kase.answer.stdout, rb, dir),
                                    Ze0::Harness::Normalize.bytes(kase.answer.stderr, rb, dir),
                                    kase.answer.code, kase.answer.signal)
    # The converter's own reading, so the two never drift apart.
    program = Convert.strip(kase.program)

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
    out << "status: recorded #{want.code.inspect}, spec #{code.inspect}" unless want.code == code
    signal = seen.want[:signal]
    out << "signal: recorded #{want.signal}, spec #{signal}" unless want.signal == signal
    # The platforms whose stdout parts from macOS's, each named by its
    # own section in the recording.
    Ze0::Harness::Case::PREFIXED.each do |platform|
      recorded = Ze0::Harness::Normalize.bytes(kase.expected(platform).stdout, rb, dir)
      # Bytes, not strings: both sides come from `Normalize`, and a
      # UTF-8 string never equals the same bytes tagged binary.
      recorded = nil if recorded.b == want.stdout.b
      spec = seen.want.fetch(:elsewhere, {})[platform]
      next if recorded.nil? ? spec.nil? : same?(recorded, spec)

      out << "#{platform} stdout: #{apart(text(recorded.to_s), spec.to_s)}"
    end
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

# An area at a time: every spec file it was written to, held to every
# case it came from.
def verify_area(area, taken_in = [])
  root = ConvertVerify::ROOT
  dir = File.join(root, "test", area)
  cases = (Dir[File.join(dir, "*.rb")] + taken_in).sort.filter_map do |rb|
    kase = (Ze0::Harness::Case.read(rb) rescue next)
    kase.recorded? ? [rb, kase.program] : nil
  end
  plan = Subjects.plan(area, cases)

  seen = {}
  Dir[File.join(root, "test/spec", area, "*_test.rb")].sort.each do |spec|
    ConvertVerify.load(spec).each { |ex| (seen[[spec, ex.name]] = ex) }
  end

  differences = []
  checked = 0
  plan.each do |rb, (path, _, drop)|
    ex, why = Convert.read(rb)
    next unless ex # refused by the converter, and named there

    name = Subjects.name_for(rb, drop)
    spec = File.join(root, "test/spec", path)
    example = seen.delete([spec, name])
    rel = rb.delete_prefix("#{root}/")
    unless example
      differences << "#{rel}: no example #{name.inspect} in #{path}"
      next
    end

    checked += 1
    differences.concat(ConvertVerify.differences(example, Ze0::Harness::Case.read(rb), rb))
  end
  seen.each_key { |spec, name| differences << "#{spec.delete_prefix("#{root}/")}: #{name.inspect} matches no case" }

  differences.first(5).each { |why| warn why }
  puts format("%-24s %4d example(s) checked, %d difference(s)", area, checked, differences.size)
  differences.size
end

if ARGV.first == "--area"
  ARGV.shift
  abort("usage: ruby tools/convert_verify.rb --area <area>...") if ARGV.empty?
  taken = Convert.taken_in
  exit(ARGV.sum { |area| verify_area(area, taken[area]) }.zero? ? 0 : 1)
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
