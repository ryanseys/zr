# frozen_string_literal: true

# The net a spec rewrite works over.
#
#   rake spec:fingerprint                      # a digest per example
#   rake 'spec:verify[HEAD]'                   # what moved since a revision
#   rake 'spec:verify[HEAD --renames]'         # ... allowing descriptions to change
#   rake spec:check                            # the formatting conventions
#   rake spec:audit                            # what is still to clean up
#
# `test/spec` was converted from a flat corpus of standalone programs, and
# the conversion left machine-generated shapes behind: slugged
# descriptions, hand-restated `path:`, whole programs escaped onto one
# line, and examples that bundle several tests. Cleaning those up means
# editing thousands of examples, and the only safe way to do that is to
# be able to prove an edit changed nothing but what it meant to.
#
# `Ze0::Reader` reads a spec file without compiling or running anything,
# and hands back what each example *is*: its sentence, its program, the
# keywords it was written with, and the answer it claims. Two readings
# that agree are two files that mean the same. It compiles nothing, so
# the whole suite fingerprints in seconds.
#
# What this cannot see: the reader is blind to anything outside an
# example -- file comments, `require` lines, blank-line structure -- and
# it evaluates a guard (`Ze0::Spec.platform`) once, down one branch. So
# it proves meaning is preserved, not that the file is unchanged. Pair it
# with `rake oracle`, which asks ruby the same question the spec asks.

require "digest"

module SpecNet
  ROOT = File.expand_path("..", __dir__)

  # What a guard asks of the machine. The real ones live in
  # `test/support/spec.rb`, which loads the whole compiler; a tool that
  # compiles nothing answers them itself, the way `rake oracle` does.
  def self.stub!
    require_relative "../test/support/reader"
    return if defined?(Ze0::Spec.platform)

    Ze0.const_set(:Spec, Module.new) unless Ze0.const_defined?(:Spec, false)
    Ze0::Spec.define_singleton_method(:platform) { "macos" }
    Ze0::Spec.define_singleton_method(:need?) { |_name| true }
  end

  module_function

  def files(path)
    full = File.expand_path(path, ROOT)
    File.directory?(full) ? Dir[File.join(full, "**/*_test.rb")].sort : [full]
  end

  def rel(path) = path.delete_prefix("#{ROOT}/")

  # Every example a path holds, as `[file, name, digest, example]`.
  #
  # `source` and the `files:` bytes are compared as bytes: a fixture
  # moved from an inline literal to a file on disk comes back tagged
  # ASCII-8BIT rather than UTF-8, and both roads write it with
  # `File.binwrite`, so the tag is not something any run can see.
  def examples(path, renames: false)
    Ze0::Reader.read(path).map do |e|
      parts = [e.about, e.source&.b, bytes(e.given), bytes(e.want)]
      parts.unshift(e.name, e.kwargs[:path]) unless renames
      [rel(path), e.name, Digest::SHA256.hexdigest(Marshal.dump(parts)), e]
    end
  end

  # A hash or array with every string in it reduced to its bytes, so a
  # comparison is about content and not about an encoding tag.
  def bytes(value)
    case value
    when String then value.b
    when Hash   then value.to_h { |k, v| [k, bytes(v)] }
    when Array  then value.map { |v| bytes(v) }
    when Exception then [value.class.name, value.message]
    else value
    end
  end
end

namespace :spec do
  desc "A digest per example, to diff a rewrite against: rake spec:fingerprint > before.txt"
  task :fingerprint, [:path] do |_, args|
    SpecNet.stub!
    argv = args[:path].to_s.split
    argv = ["test/spec"] if argv.empty?
    n = 0
    argv.flat_map { |p| SpecNet.files(p) }.each do |file|
      SpecNet.examples(file).each { |f, name, digest, _| puts "#{digest}  #{f}  #{name}"; n += 1 }
    end
    warn "#{n} example(s) fingerprinted"
  end

  desc "What moved since a revision: rake 'spec:verify[HEAD]', or '[HEAD --renames]' to allow new sentences"
  task :verify, [:args] do |_, args|
    SpecNet.stub!
    require "tmpdir"
    argv = args[:args].to_s.split
    renames = argv.delete("--renames")
    rev = argv.shift || "HEAD"
    paths = argv.empty? ? ["test/spec"] : argv

    apart = []
    checked = 0
    Dir.mktmpdir("ze0-verify-") do |work|
      paths.flat_map { |p| SpecNet.files(p) }.each do |file|
        rel = SpecNet.rel(file)
        was = IO.popen(["git", "show", "#{rev}:#{rel}"], err: File::NULL, &:read)
        next warn "#{rel}: not in #{rev}, skipped" unless $?.success?

        before = File.join(work, "before.rb")
        File.write(before, was)
        old = SpecNet.examples(before, renames: renames)
        new = SpecNet.examples(file, renames: renames)
        checked += new.size

        # Compare by position, not as a set: a set is invariant under
        # permutation, and position is the only stable key while the
        # sentences themselves are what is changing.
        if old.size != new.size
          apart << "#{rel}: #{old.size} example(s) became #{new.size}"
          next
        end
        old.zip(new).each do |(_, was_name, was_digest, _), (_, name, digest, e)|
          apart << "#{rel}: #{name}: the example raised #{e.want[:error].class}" if e.want[:error]
          next if was_digest == digest

          apart << "#{rel}: #{was_name.inspect} -> #{name.inspect}: #{renames ? "more than the sentence" : "the example"} changed"
        end
      end
    end
    apart.each { |line| warn line }
    puts format("%d example(s) checked against %s, %d apart", checked, rev, apart.size)
    exit(apart.empty? ? 0 : 1)
  end
end

# The shapes a spec file is written in. None of this changes what an
# example means, which is why it is a check and not a rewrite: the
# repository has no linter, and a house style this particular is better
# held by a task that knows about `ze0` and `must_answer` than by a
# general one that does not.
module SpecStyle
  # Wide enough for a table row, narrow enough to read beside another
  # file. The corpus conversion left single lines of 13 KB and more.
  COLUMNS = 120

  # A program is `RUBY`, an answer is `OUT`, and a platform's answer is
  # its own name. Anything else is a one-off from the old corpus.
  TAGS = %w[RUBY OUT LINUX WASI].freeze

  module_function

  # Every complaint about one file, as `[line, why]`.
  def faults(path)
    out = []
    File.readlines(path).each_with_index do |line, i|
      n = i + 1
      out << [n, "trailing whitespace"] if line.rstrip != line.chomp
      out << [n, "#{line.chomp.size} columns, over #{COLUMNS}"] if line.chomp.size > COLUMNS
      line.scan(/<<([-~])('?)([A-Z_]+)\2/) do |squiggly, quote, tag|
        out << [n, "heredoc <<#{squiggly}#{tag}: use <<~"] if squiggly != "~"
        out << [n, "heredoc #{tag}: not one of #{TAGS.join(", ")}"] unless TAGS.include?(tag)
        # A Ruby program in an interpolating heredoc has live `#{}` in
        # it, which is a footgun and not a feature.
        out << [n, "heredoc <<~#{tag}: quote the tag, or #\{\} in the program runs"] if quote.empty?
      end
    end
    out
  end
end

namespace :spec do
  desc "The formatting conventions: rake 'spec:check[test/spec/core/string]'"
  task :check, [:path] do |_, args|
    argv = args[:path].to_s.split
    argv = ["test/spec"] if argv.empty?
    files = argv.flat_map { |p| SpecNet.files(p) }
    faults = files.flat_map { |f| SpecStyle.faults(f).map { |n, why| "#{SpecNet.rel(f)}:#{n}: #{why}" } }
    faults.each { |line| warn line }
    puts format("%d file(s) checked, %d fault(s)", files.size, faults.size)
    exit(faults.empty? ? 0 : 1)
  end
end
