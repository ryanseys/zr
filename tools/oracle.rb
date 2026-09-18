# frozen_string_literal: true

# Is every literal a spec asserts still ruby's word?
#
#   ruby tools/oracle.rb test/spec/core/string           # an area
#   ruby tools/oracle.rb test/spec                       # all of them
#   ruby tools/oracle.rb test/spec/core/string/frozen_test.rb -n frozen
#
# The contract is that ruby 4.0.6 is the only source of right answers.
# The specs were written by lifting the answers ruby had already
# recorded, so every literal in them traces to ruby -- and this is what
# holds that true as the files are edited by hand afterwards.
#
# It compiles nothing. Each example's program is written to a temporary
# directory with its own fixtures beside it, run under the ruby the
# `.ruby-version` pins, scrubbed the way the spec road scrubs an answer,
# and held to what the example asserts. An example that skips is not
# asked: a skipped example makes no claim about ruby.

require "fileutils"
require "optparse"
require "rbconfig"
require "tmpdir"
require_relative "../test/support/reader"
require_relative "../test/support/harness/answer"
require_relative "../test/support/harness/child"

# What a guard asks of the machine. The real ones live in
# `test/support/spec.rb`, which loads the whole compiler; a tool that
# compiles nothing answers them itself.
module Ze0
  module Spec
    def self.platform = "macos"
    def self.need?(_name) = true
  end
end

module Oracle
  ROOT = File.expand_path("..", __dir__)

  # Long enough for the slowest program a spec holds, and short enough
  # that one that loops does not hold the run.
  LIMIT = 120

  module_function

  # Every spec file under `path`, which may be one file or a directory.
  def files(path)
    full = File.expand_path(path, ROOT)
    File.directory?(full) ? Dir[File.join(full, "**/*_test.rb")].sort : [full]
  end

  # What ruby says when it runs `example`'s program, scrubbed the way
  # the spec road scrubs what ze0's binary says.
  def ask(example)
    kwargs = example.kwargs
    Dir.mktmpdir("ze0-oracle-") do |work|
      # `/var` is a link to `/private/var` on macOS, and a program that
      # prints a path of its own prints the resolved one; the scrub has
      # to be looking at the same bytes.
      run = File.join(File.realpath(work), "run")
      rb = File.join(run, kwargs.fetch(:path, "spec.rb"))
      FileUtils.mkdir_p(File.dirname(rb))
      File.write(rb, example.source)
      kwargs.fetch(:files, {}).each do |name, bytes|
        beside = File.expand_path(name, File.dirname(rb))
        FileUtils.mkdir_p(File.dirname(beside))
        bytes.is_a?(Hash) ? File.symlink(bytes.fetch(:symlink), beside) : File.binwrite(beside, bytes)
      end

      argv = [RbConfig.ruby, *kwargs.fetch(:ruby, []), kwargs.fetch(:path, "spec.rb"), *kwargs.fetch(:argv, [])]
      out, = Ze0::Harness::Child.run(argv, cwd: run, stdin: kwargs[:stdin], env: kwargs.fetch(:env, {}),
                                           seconds: LIMIT, megabytes: Ze0::Harness::Child::RUN_MB)
      return nil unless out.code.is_a?(Integer)

      Ze0::Harness::Normalize.answer(out, rb, run)
    end
  end

  # Where the example's claim and ruby's answer part, in words.
  def differences(example, answer)
    want = example.want
    out = []
    out << part("stdout", want[:stdout], text(answer.stdout))
    out << part("stderr", want.fetch(:stderr, ""), text(answer.stderr))
    status = want.fetch(:status, 0)
    out << "status: spec #{status.inspect}, ruby #{answer.code.inspect}" unless status == answer.code
    signal = want[:signal]
    out << "signal: spec #{signal.inspect}, ruby #{answer.signal.inspect}" unless signal == answer.signal
    out.compact
  end

  def part(name, spec, ruby)
    return nil if spec.to_s == ruby

    n = spec.to_s.lines.zip(ruby.lines).index { |a, b| a != b } || 0
    "#{name}: line #{n + 1}: spec #{spec.to_s.lines[n].inspect}, ruby #{ruby.lines[n].inspect}"
  end

  def text(bytes)
    out = bytes.dup.force_encoding(Encoding::UTF_8)
    out.valid_encoding? ? out : bytes
  end

  # One file: every example ruby is asked about, and what parted.
  def check(path, filter)
    rel = path.delete_prefix("#{ROOT}/")
    asked = 0
    skipped = 0
    apart = []
    Ze0::Reader.read(path).each do |example|
      next if filter && !example.name.match?(filter)
      # An example that skips makes no claim about ruby, and one that
      # never called `ze0` has nothing to ask about.
      next skipped += 1 if example.want.key?(:skip) || example.source.nil?

      answer = ask(example)
      next apart << "#{rel}: #{example.name}: ruby did not finish" if answer.nil?

      asked += 1
      differences(example, answer).each { |why| apart << "#{rel}: #{example.name}: #{why}" }
    end
    [asked, skipped, apart]
  end
end

if $PROGRAM_NAME == __FILE__
  filter = nil
  OptionParser.new do |o|
    o.on("-n PATTERN", "only examples whose name matches") { |v| filter = Regexp.new(v) }
  end.parse!(ARGV)
  abort "usage: ruby tools/oracle.rb [-n PATTERN] <spec file or directory>..." if ARGV.empty?

  asked = skipped = 0
  apart = []
  ARGV.flat_map { |path| Oracle.files(path) }.each do |file|
    a, s, why = Oracle.check(file, filter)
    asked += a
    skipped += s
    apart.concat(why)
    why.each { |line| warn line }
    puts format("%-56s %4d asked, %2d skipped, %d apart", file.delete_prefix("#{Oracle::ROOT}/"), a, s, why.size)
  end
  puts format("%d example(s) asked, %d skipped, %d apart from ruby", asked, skipped, apart.size)
  exit(apart.empty? ? 0 : 1)
end
