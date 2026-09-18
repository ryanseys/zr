# frozen_string_literal: true

# The net a spec rewrite works over.
#
#   rake 'spec:verify[HEAD]'                   # what moved since a revision
#   rake 'spec:verify[HEAD --renames]'         # ... allowing descriptions to change
#   rake spec:fingerprint                      # a digest per example, to diff yourself
#   rake spec:check                            # the formatting conventions
#   rake spec:tidy                             # fix what check reports that is safe to fix
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

module SpecNet
  ROOT = File.expand_path("..", __dir__)

  # What a guard asks of the machine. The real ones live in
  # `test/support/spec.rb`, which loads the whole compiler; a tool that
  # compiles nothing answers them itself, the way `rake oracle` does.
  def self.stub!
    # Here rather than at the top of the file: a require in `rakelib/`
    # runs for `rake -T` and for every test run, which is what cbf8afe5
    # was about.
    require "digest"
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
  # its own name.
  #
  # `PROGRAM` is the other spelling of a program, and it is not a stray:
  # a `<<~` terminator may be indented, so a program that contains its
  # own `eval <<~RUBY ... RUBY` would end the outer heredoc early. Eight
  # examples need it -- see `core/object/formatting_test.rb`, where the
  # program defines a method through `eval`.
  TAGS = %w[RUBY PROGRAM OUT LINUX WASI].freeze

  module_function

  # Every complaint about one file, as `[line, why]`.
  def faults(path)
    out = []
    inside = nil
    sentences = Hash.new { |h, k| h[k] = [] }
    File.readlines(path).each_with_index do |line, i|
      n = i + 1
      out << [n, "trailing whitespace"] if line.rstrip != line.chomp

      # Inside a heredoc the DSL opened, the lines are the program under
      # test or the answer to it -- a row of a table is as long as the
      # row is, and reflowing it would change what the example asks.
      # Only the file's own code is held to a width.
      if inside
        inside = nil if line.match?(/\A\s*#{inside}\s*\z/)
        next
      end
      inside = line[/(?:\bze0\(|\bmust_answer )<<[-~]'?([A-Z_]+)/, 1]

      # Collected here rather than in a pass of its own so that an `it`
      # written *inside* a program under test -- an rspec suite has
      # them -- is not mistaken for one of this file's.
      if (name = line[/\A\s*it ("(?:[^"\\]|\\.)*") do\n?\z/, 1])
        sentences[name] << n
      end

      out << [n, "#{line.chomp.size} columns, over #{COLUMNS}"] if line.chomp.size > COLUMNS
      # Only a heredoc this file opens as an argument to the DSL. A
      # program under test may open one of its own -- `eval(<<~SRC)`, a
      # Gemfile, a PEM -- and an expected answer may quote the text of
      # one, as the Ripper and AST examples do. Neither is this file's
      # shape to hold.
      line.scan(/(?:\bze0\(|\bmust_answer )<<([-~])('?)([A-Z_]+)/) do |squiggly, quote, tag|
        out << [n, "heredoc <<#{squiggly}#{tag}: use <<~"] if squiggly != "~"
        out << [n, "heredoc #{tag}: not one of #{TAGS.join(", ")}"] unless TAGS.include?(tag)
        # A Ruby program in an interpolating heredoc has live `#{}` in
        # it, which is a footgun and not a feature.
        out << [n, "heredoc <<~#{tag}: quote the tag, or #\{\} in the program runs"] if quote.empty?
      end
    end
    # Two examples in one file with the same sentence. Minitest takes
    # them both -- it numbers the methods it defines -- so nothing
    # fails, and a failure report then names a sentence that matches two
    # examples. A campaign that rewrites thousands of descriptions walks
    # into this, which is why it is checked rather than trusted.
    sentences.reject { |_, lines| lines.one? }
             .each { |name, lines| lines.drop(1).each { |n| out << [n, "#{name} is also line #{lines.first}"] } }
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

namespace :spec do
  desc "Fix what spec:check reports that is safe to fix: rake 'spec:tidy[test/spec/core/string]'"
  task :tidy, [:path] do |_, args|
    argv = args[:path].to_s.split
    argv = ["test/spec"] if argv.empty?
    changed = 0
    lines = 0
    argv.flat_map { |p| SpecNet.files(p) }.each do |file|
      was = File.read(file)
      # Only whitespace-only lines. A line with content and trailing
      # space may be inside a string the program prints, where the space
      # is the answer; a line that is nothing but space is a blank line
      # wherever it sits, and `<<~` already ignores it when it works out
      # how far to dedent.
      now = was.gsub(/^[ \t]+$/, "")
      # A comment line with nothing after the `#` but space. In a
      # program that space is invisible; the oracle is what says so,
      # since in an answer it could be the answer.
      now = now.gsub(/^([ \t]*#)[ \t]+$/, '\\1')
      next if now == was

      File.write(file, now)
      changed += 1
      lines += was.lines.count { |l| l.match?(/^[ \t]+$/) }
    end
    puts format("%d file(s) tidied, %d blank line(s) emptied", changed, lines)
    puts "now run: rake 'oracle[<path>]' -- the program text changed, so ruby is the judge"
  end
end

# Splitting an example that holds several.
#
# 95 examples carry `# === <name> ===` banners marking 457 tests that
# were separate programs before the corpus conversion bundled them. One
# `must_answer` covers all of them, so a failure anywhere is one diff of
# several hundred lines and the example's name -- `bundle class 07` --
# says nothing about any of it.
#
# A section is only safe to lift out if it does not depend on the ones
# before it, and that is not a thing to decide by reading. Each `t_<name>`
# is called immediately after it is defined, so a section's output is a
# contiguous slice of the bundle's: run the sections separately, and if
# their answers joined are the bundle's answer, they did not interact.
# If they did, the join differs and the bundle is left alone.
module SpecSplit
  BANNER = /^# === (.+) ===$/
  MANIFEST = /\A# Bundled tests:\n(?:#(?:   .*)?\n)*/

  module_function

  # `[preamble, [[name, body], ...]]`, or nil when there are no banners.
  def sections(source)
    return nil unless source&.match?(BANNER)

    head, *rest = source.split(BANNER)
    return nil if rest.empty?

    [head.sub(MANIFEST, "").strip, rest.each_slice(2).map { |name, body| [name.strip, body.to_s] }]
  end

  # What ruby says for one candidate program, through the oracle's own
  # machinery so the scrub and the environment are the same.
  def ask(example, source)
    probe = example.dup
    probe.source = source
    Oracle.ask(probe)
  end
end

namespace :spec do
  desc "Which bundled examples can be split, and into what: rake 'spec:split[test/spec/core/hash]'"
  task :split, [:path] do |_, args|
    SpecNet.stub!
    argv = args[:path].to_s.split
    argv = ["test/spec"] if argv.empty?

    splittable = 0
    coupled = 0
    gained = 0
    argv.flat_map { |p| SpecNet.files(p) }.each do |file|
      Ze0::Reader.read(file).each do |e|
        head, parts = SpecSplit.sections(e.source)
        next unless parts

        answers = parts.map { |_, body| SpecSplit.ask(e, "#{head}\n\n#{body}") }
        joined = answers.map { |a| a&.stdout.to_s }.join
        if answers.any?(&:nil?) || joined != e.want[:stdout].to_s
          coupled += 1
          warn "#{SpecNet.rel(file)}: #{e.name}: sections interact, left whole"
          next
        end

        splittable += 1
        gained += parts.size - 1
        puts format("%-52s %-22s %d section(s)", SpecNet.rel(file), e.name, parts.size)
      end
    end
    puts format("%d example(s) split cleanly into %d, %d left whole", splittable, splittable + gained, coupled)
  end
end

# What ruby answers for a program that is not in a spec file yet.
#
# The hand splits Phase 3 left -- the examples with no banner to cut on
# -- need a new literal for every fragment, and the repo's rule is that
# a literal is never written by hand. This asks ruby through the
# oracle's own machinery, so the path, the scrub and the environment are
# the ones the example will run under, and prints the answer already
# shaped as the assertion to paste.
#
#   rake 'spec:ask[test/spec/core/thread/thread_test.rb frag.rb]'
#   rake 'spec:ask[test/spec/stdlib/etc/etc_test.rb frag.rb -n "reads a group"]'
#
# `-n` borrows an existing example's keywords, for a fragment that needs
# the `files:` or `argv:` its bundle had.
module SpecAsk
  module_function

  # The assertion for an answer, in the shape the suite writes it.
  def assertion(answer)
    tail = []
    tail << "stderr: #{dump(answer.stderr)}" unless answer.stderr.empty?
    tail << "status: #{answer.code}" unless answer.code.zero?
    tail << "signal: #{answer.signal.inspect}" if answer.signal
    head = "_(result).must_answer"
    body = answer.stdout
    return "#{head} #{dump(body)}#{tail.empty? ? "" : ", #{tail.join(", ")}"}" unless body.include?("\n")

    "#{head} <<~'OUT'#{tail.empty? ? "" : ", #{tail.join(", ")}"}\n" \
      "#{body.lines.map { |l| "  #{l}" }.join}OUT"
  end

  # A literal with the escapes the suite uses, not `inspect`'s -- which
  # would turn a UTF-8 answer into `\u` escapes.
  def dump(bytes)
    out = bytes.dup.force_encoding(Encoding::UTF_8)
    out = bytes unless out.valid_encoding?
    %("#{out.gsub("\\", "\\\\\\\\").gsub('"', '\"').gsub("\n", '\n').gsub("\t", '\t').gsub("\e", '\e')}")
  end
end

namespace :spec do
  desc "What ruby answers for a candidate program: rake 'spec:ask[<spec_file> <program.rb>]'"
  task :ask, [:args] do |_, args|
    SpecNet.stub!
    argv = args[:args].to_s.split
    borrow = nil
    OptionParser.new { |o| o.on("-n NAME", "borrow this example's keywords") { |v| borrow = v } }.parse!(argv)
    spec_file, program = argv
    raise ArgumentError, "want: rake 'spec:ask[<spec_file> <program.rb>]'" unless spec_file && program

    kwargs = { path: Ze0::Reader.path_for(spec_file) }
    if borrow
      from = Ze0::Reader.read(spec_file).find { |e| e.name == borrow }
      raise ArgumentError, "no example named #{borrow.inspect} in #{spec_file}" unless from

      kwargs = from.kwargs
    end
    example = Ze0::Reader::Example.new(name: "ask", source: File.read(program), kwargs: kwargs, want: {})
    answer = Oracle.ask(example)
    raise "ruby did not finish" unless answer

    puts SpecAsk.assertion(answer)
  end
end
