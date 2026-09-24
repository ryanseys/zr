# frozen_string_literal: true

# Checks that each literal a spec asserts is still what ruby outputs.
#
#   rake oracle                                     # every spec
#   rake 'oracle[test/spec/core/string]'            # an area
#   rake 'oracle[test/spec/core/string/frozen_test.rb -n frozen]'
#
# Ruby 4.0.6 is the only reference for correct output. Every literal in
# the specs comes from ruby's output. This task makes sure that stays
# true after people edit the spec files by hand.
#
# It compiles nothing. For each example, it writes the program and its
# fixtures to a temporary directory and runs it with the ruby that
# `.ruby-version` pins. It normalizes the output as the spec tier does,
# and compares it with what the example asserts. It does not run an
# example that skips, because that example makes no claim about ruby.

require "fileutils"
require "optparse"
require "etc"
require "rbconfig"
require "tmpdir"
require_relative "../test/support/reader"
require_relative "../test/support/harness/answer"
require_relative "../test/support/harness/child"
require_relative "../lib/zr/native/parallel"

# The machine facts that a guard reads. The real methods are in
# `test/support/spec.rb`, which loads the whole compiler. This task
# compiles nothing, so it gives its own values.
module Zr
  module Spec
    def self.platform = "macos"
    def self.need?(_name) = true
  end
end

module Oracle
  ROOT = File.expand_path("..", __dir__)

  # Seconds. Long enough for the slowest program in a spec, and short
  # enough that a program that loops forever does not stop the run.
  LIMIT = 120

  module_function

  # Every spec file under `path`, which may be one file or a directory.
  def files(path)
    full = File.expand_path(path, ROOT)
    File.directory?(full) ? Dir[File.join(full, "**/*_test.rb")].sort : [full]
  end

  # Runs `example`'s program with ruby and returns the output. It
  # normalizes the output as the spec tier normalizes a zr binary's output.
  def ask(example)
    kwargs = example.kwargs
    Dir.mktmpdir("zr-oracle-") do |work|
      # On macOS, `/var` is a link to `/private/var`. A program that prints
      # its own path prints the resolved path, so the normalization must
      # use the resolved path too.
      run = File.join(File.realpath(work), "run")
      rb = File.join(run, kwargs.fetch(:path, "spec.rb"))
      FileUtils.mkdir_p(File.dirname(rb))
      File.write(rb, example.source)
      kwargs.fetch(:files, {}).each do |name, bytes|
        beside = File.expand_path(name, File.dirname(rb))
        raise ArgumentError, "the fixture #{name.inspect} lands on the program itself" if beside == rb

        FileUtils.mkdir_p(File.dirname(beside))
        bytes.is_a?(Hash) ? File.symlink(bytes.fetch(:symlink), beside) : File.binwrite(beside, bytes)
      end

      argv = [RbConfig.ruby, *kwargs.fetch(:ruby, []), kwargs.fetch(:path, "spec.rb"), *kwargs.fetch(:argv, [])]
      # Use `BARE_RUBY`, because a bare ruby made the recordings, not a
      # ruby under `bundle exec`. The example's own `env:` has priority.
      env = Zr::Harness::Child::BARE_RUBY.merge(kwargs.fetch(:env, {}))
      out, = Zr::Harness::Child.run(argv, cwd: run, stdin: kwargs[:stdin], env: env,
                                           seconds: LIMIT, megabytes: Zr::Harness::Child::RUN_MB)
      return nil unless out.code.is_a?(Integer)

      Zr::Harness::Normalize.answer(out, rb, run)
    end
  end

  # Describes each difference between the example's assertion and ruby's
  # output.
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

  # Runs `check` on each of `files` and yields each file with its result,
  # in order. Forked workers (one for each core, at most 12) share the
  # files. Each example starts its own ruby, so the workers share nothing.
  # The full tier starts about 7,000 rubies, too slow in one process.
  def each_checked(files, filter)
    workers = [Etc.nprocessors, 12].min
    answers = Zr::Native::Parallel.map(files, jobs: workers, weight: ->(_) { 1 }) { |file| check(file, filter) }
    files.zip(answers).each { |file, answer| yield file, answer }
  end

  # Checks one file. Returns the count of examples run, the count
  # skipped, and the differences.
  def check(path, filter)
    rel = path.delete_prefix("#{ROOT}/")
    asked = 0
    skipped = 0
    apart = []
    Zr::Reader.read(path).each do |example|
      next if filter && !example.name.match?(filter)
      # An example that the reader could not load is a broken spec, not a
      # skipped one. If it counted as skipped, a bad edit could remove
      # examples from the run, and the run would still report no
      # differences.
      if (e = example.want[:error])
        next apart << "#{rel}: #{example.name}: the example raised #{e.class}: #{e.message}"
      end

      # An example that skips makes no claim about ruby. An example that
      # does not call `zr` has no program to run.
      next skipped += 1 if example.want.key?(:skip) || example.source.nil?

      answer = ask(example)
      next apart << "#{rel}: #{example.name}: ruby did not finish" if answer.nil?

      asked += 1
      differences(example, answer).each { |why| apart << "#{rel}: #{example.name}: #{why}" }
    end
    [asked, skipped, apart]
  end
end

# Runs each spec program with the ruby that `.ruby-version` pins, and
# checks the output against what its example asserts. It compiles nothing.
desc "Every spec literal re-checked against ruby 4.0.6: rake 'oracle[test/spec/core/string]'"
task :oracle, [:path] do |_, args|
  argv = args[:path].to_s.split
  filter = nil
  OptionParser.new do |o|
    o.on("-n PATTERN", "only examples whose name matches") { |v| filter = Regexp.new(v) }
  end.parse!(argv)
  argv = ["test/spec"] if argv.empty?

  asked = skipped = 0
  apart = []
  files = argv.flat_map { |path| Oracle.files(path) }
  Oracle.each_checked(files, filter) do |file, (a, s, why)|
    asked += a
    skipped += s
    apart.concat(why)
    why.each { |line| warn line }
    puts format("%-56s %4d asked, %2d skipped, %d apart", file.delete_prefix("#{Oracle::ROOT}/"), a, s, why.size)
  end
  puts format("%d example(s) asked, %d skipped, %d apart from ruby", asked, skipped, apart.size)
  exit(apart.empty? ? 0 : 1)
end
