# frozen_string_literal: true

# Tools that make large edits to spec files safe.
#
#   rake 'spec:verify[HEAD]'                   # what changed since a revision
#   rake 'spec:verify[HEAD --renames]'         # ... and permit changed descriptions
#   rake 'spec:verify[HEAD~3 test/spec/core]'  # ... in one area
#   rake spec:fingerprint                      # a digest for each example, to diff yourself
#   rake spec:check                            # the formatting conventions
#   rake spec:tidy                             # fix the safe faults that check reports
#
# `Zr::Reader` reads a spec file without compiling or running anything.
# It returns the parts of each example: its sentence, its program, its
# keywords, and its expected output. If two files give the same parts,
# they have the same meaning. The full suite fingerprints in seconds.
#
# Limits: the reader does not see anything outside an example (file
# comments, `require` lines, blank lines). It reads a guard (`only:`)
# against this host only. Thus it shows that the
# meaning is the same, not that the file is the same. Use it with
# `rake oracle`, which checks each example against ruby.

module SpecNet
  ROOT = File.expand_path("..", __dir__)

  # Loads the reader. The requires are here, not at the top of the
  # file, because rake loads each file in `rakelib/` for `rake -T` and
  # for each test run.
  def self.load!
    require "digest"
    require_relative "../test/support/reader"
  end

  module_function

  def files(path)
    full = File.expand_path(path, ROOT)
    File.directory?(full) ? Dir[File.join(full, "**/*_test.rb")].sort : [full]
  end

  def rel(path) = path.delete_prefix("#{ROOT}/")

  # Every example in a path, as `[file, name, digest, example, parts]`.
  #
  # `source` and the `files:` contents are compared as bytes. A fixture
  # in a file on disk has the ASCII-8BIT tag, but an inline literal has
  # UTF-8. Both zr and ruby write it with `File.binwrite`, so no run can
  # see the tag.
  #
  # `as:` is the correct location of the file. It is different from the
  # read location when an older revision is in a temporary file. The
  # default `path:` comes from the spec file's location. Without `as:`,
  # every example of the old revision would show a changed path.
  def examples(path, renames: false, as: path)
    Zr::Reader.read(path).map do |e|
      parts = { "describe" => e.about, "program" => e.source&.b,
                "keywords" => bytes(e.given), "answer" => bytes(e.want) }
      unless renames
        written = e.given[:path] || Zr::Reader.path_for(as)
        parts = { "sentence" => e.name, "path" => written }.merge(parts)
      end
      [rel(as), e.name, Digest::SHA256.hexdigest(Marshal.dump(parts.values)), e, parts]
    end
  end

  # The names of the parts of an example that differ, so that a report
  # tells which part changed.
  def moved(was, now)
    was.keys.select { |k| was[k] != now[k] }
  end

  # Changes each string in a hash or array to its bytes, so that a
  # comparison ignores the encoding tag.
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
    SpecNet.load!
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
    SpecNet.load!
    require "tmpdir"
    argv = args[:args].to_s.split
    renames = argv.delete("--renames")
    rev = argv.shift || "HEAD"
    paths = argv.empty? ? ["test/spec"] : argv

    apart = []
    checked = 0
    Dir.mktmpdir("zr-verify-") do |work|
      paths.flat_map { |p| SpecNet.files(p) }.each do |file|
        rel = SpecNet.rel(file)
        was = IO.popen(["git", "show", "#{rev}:#{rel}"], err: File::NULL, &:read)
        next warn "#{rel}: not in #{rev}, skipped" unless $?.success?

        before = File.join(work, "before.rb")
        File.write(before, was)
        old = SpecNet.examples(before, renames: renames, as: file)
        new = SpecNet.examples(file, renames: renames)
        checked += new.size

        # Compare by position, not as a set. A set does not see a change
        # of order, and the position is the only stable key when the
        # sentences change.
        if old.size != new.size
          apart << "#{rel}: #{old.size} example(s) became #{new.size}"
          next
        end
        old.zip(new).each do |(_, was_name, was_digest, _, was_parts), (_, name, digest, e, parts)|
          apart << "#{rel}: #{name}: the example raised #{e.want[:error].class}" if e.want[:error]
          next if was_digest == digest

          why = SpecNet.moved(was_parts, parts).join(", ")
          apart << "#{rel}: #{was_name.inspect} -> #{name.inspect}: #{why} changed"
        end
      end
    end
    apart.each { |line| warn line }
    puts format("%d example(s) checked against %s, %d apart", checked, rev, apart.size)
    exit(apart.empty? ? 0 : 1)
  end
end

# The format rules for a spec file. None of them change the meaning of
# an example. A task that knows about `zr` and `must_answer` checks them
# better than a general linter.
module SpecStyle
  # Wide enough for a table row, and narrow enough to read next to
  # another file.
  COLUMNS = 120

  # The tags whose body is ruby's output. The tasks here must not change
  # it: a trailing space in the output is a byte that ruby wrote.
  ANSWERS = %w[OUT ERR LINUX WASI].freeze

  # A program is `RUBY`, its stdout is `OUT`, its stderr is `ERR`, and
  # the output on a given platform uses the platform name.
  #
  # `PROGRAM` is also a program tag. A `<<~` terminator can be indented,
  # so a program that contains `eval <<~RUBY ... RUBY` would end an outer
  # `RUBY` heredoc too early. Eight examples need it (for example,
  # `core/object/formatting_test.rb`, which defines a method with `eval`).
  TAGS = %w[RUBY PROGRAM OUT ERR LINUX WASI].freeze

  # Sentences that a generator writes into more than one file on purpose,
  # as they are written in the source. `rake gen:dispatch`
  # (`rakelib/dispatch.rake`) writes this one into six files, one for
  # each class it tests. Each file's `describe` gives the class, so the
  # sentence does not need it.
  GENERATED = ["subclass sees only the calls ruby makes"].map(&:inspect).freeze

  # Where the DSL opens a heredoc: the program, its stdout, its stderr,
  # and the output for a given platform. Only these. A program under
  # test can open its own heredoc (`eval(<<~SRC)`, a Gemfile, a PEM), and
  # an expected output can contain heredoc text (as the Ripper examples
  # do). These rules do not apply to those.
  OPENS = /(?:\bzr\(|\bmust_answer |\b(?:stderr|linux|wasi): )<<[-~]'?([A-Z_]+)/

  module_function

  # Yields each line of a spec file with the tag of the DSL heredoc that
  # contains it, or nil for the file's own code. All the rules below use
  # this one method, so that they cannot disagree.
  def each_line(path)
    open = []
    File.readlines(path).each_with_index do |line, i|
      yield line, i + 1, open.first
      if open.any?
        # A `<<~` terminator can be indented, so match the tag only.
        open.shift if line.match?(/\A\s*#{open.first}\s*\z/)
      else
        # One line can open two heredocs: `must_answer <<~'OUT', stderr:
        # <<~'ERR'`. Ruby reads their bodies in the order of the openers.
        open = line.scan(OPENS).flatten
      end
    end
  end

  # The sentences of one file's examples, as `{name => [line, ...]}`.
  # This ignores an `it` inside a program under test (for example, in an
  # rspec suite).
  def sentences(path)
    found = Hash.new { |h, k| h[k] = [] }
    each_line(path) do |line, n, inside|
      next if inside
      (name = line[/\A\s*it ("(?:[^"\\]|\\.)*") do\n?\z/, 1]) && found[name] << n
    end
    found
  end

  # Finds a sentence that two FILES use. The rule in `faults` checks for
  # duplicates in one file; this checks across files. Thus a sentence in
  # a failure report or a `-n` filter identifies only one example.
  def crossed(paths)
    seen = {}
    paths.flat_map do |path|
      sentences(path).filter_map do |name, lines|
        next if GENERATED.include?(name)

        first = (seen[name] ||= path)
        [path, lines.first, "#{name} is also #{SpecNet.rel(first)}"] unless first.equal?(path)
      end
    end
  end

  # Every complaint about one file, as `[line, why]`.
  def faults(path)
    out = []
    each_line(path) do |line, n, inside|
      out << [n, "trailing whitespace"] if line.rstrip != line.chomp && !ANSWERS.include?(inside)

      # Inside a DSL heredoc, the lines are the program under test or its
      # output. A change to their width would change the example. Only the
      # file's own code has a width limit.
      next if inside

      out << [n, "#{line.chomp.size} columns, over #{COLUMNS}"] if line.chomp.size > COLUMNS
      line.scan(/(?:\bzr\(|\bmust_answer |\b(?:stderr|linux|wasi): )<<([-~])('?)([A-Z_]+)/) do |squiggly, quote, tag|
        out << [n, "heredoc <<#{squiggly}#{tag}: use <<~"] if squiggly != "~"
        out << [n, "heredoc #{tag}: not one of #{TAGS.join(", ")}"] unless TAGS.include?(tag)
        # In an interpolating heredoc, each `#{}` in the program runs in
        # the test, not in the program. That is almost never intended.
        out << [n, "heredoc <<~#{tag}: quote the tag, or #\{\} in the program runs"] if quote.empty?
      end
    end
    # Two examples in one file with the same sentence. Minitest accepts
    # both (it numbers the methods it defines), so nothing fails. But a
    # failure report then gives a sentence that matches two examples.
    sentences(path).reject { |_, lines| lines.one? }
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
    # Only across the files given to this run. A run on one directory
    # cannot see a sentence outside it.
    faults += SpecStyle.crossed(files).map { |f, n, why| "#{SpecNet.rel(f)}:#{n}: #{why}" }
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
      # Change only lines that contain only whitespace. A line with text
      # and a trailing space can be in a string that the program prints,
      # where the space is part of the output. A whitespace-only line is
      # a blank line in all places, and `<<~` ignores it when it removes
      # indentation.
      now = was.gsub(/^[ \t]+$/, "")
      # A comment line with only spaces after the `#`. In a program, the
      # space has no effect. In an expected output it could matter, so
      # run `rake oracle` after this task.
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

# Finds bundled examples that can be split into smaller examples.
#
# Some examples contain `# === <name> ===` banners. Each banner starts a
# section that is a separate test. One `must_answer` covers all the
# sections, so a failure gives one large diff, and the example name does
# not identify the section.
#
# A section is safe to split out only if it does not depend on the
# sections before it. Each `t_<name>` is called immediately after its
# definition, so the output of a section is a contiguous part of the
# bundle's output. The task runs each section separately. If the joined
# outputs equal the bundle's output, the sections are independent. If
# not, the task leaves the bundle as it is.
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

  # Runs one candidate program with ruby through `Oracle.ask`, so that the
  # normalization and the environment are the same as `rake oracle`.
  def ask(example, source)
    probe = example.dup
    probe.source = source
    Oracle.ask(probe)
  end
end

namespace :spec do
  desc "Which bundled examples can be split, and into what: rake 'spec:split[test/spec/core/hash]'"
  task :split, [:path] do |_, args|
    SpecNet.load!
    argv = args[:path].to_s.split
    argv = ["test/spec"] if argv.empty?

    splittable = 0
    coupled = 0
    gained = 0
    argv.flat_map { |p| SpecNet.files(p) }.each do |file|
      Zr::Reader.read(file).each do |e|
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

# Runs a program that is not yet in a spec file with ruby, and prints
# its output as an assertion.
#
# The rule is that nobody writes an expected output by hand. This task
# runs the program through `Oracle.ask`, with the same path,
# normalization and environment as the example will have. It prints the
# output in the form of the assertion to paste.
#
#   rake 'spec:ask[test/spec/core/thread/thread_test.rb frag.rb]'
#   rake 'spec:ask[test/spec/stdlib/etc/etc_test.rb frag.rb -n "reads a group"]'
#
# `-n` uses the keywords of an existing example, for a program that needs
# that example's `files:` or `argv:`.
module SpecAsk
  module_function

  # The assertion for an output, in the form that the suite uses.
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

  # A literal with the escapes that the suite uses. `inspect` is not
  # correct here, because it changes UTF-8 output into `\u` escapes.
  def dump(bytes)
    out = bytes.dup.force_encoding(Encoding::UTF_8)
    out = bytes unless out.valid_encoding?
    %("#{out.gsub("\\", "\\\\\\\\").gsub('"', '\"').gsub("\n", '\n').gsub("\t", '\t').gsub("\e", '\e')}")
  end
end

namespace :spec do
  desc "What ruby answers for a candidate program: rake 'spec:ask[<spec_file> <program.rb>]'"
  task :ask, [:args] do |_, args|
    SpecNet.load!
    argv = args[:args].to_s.split
    borrow = nil
    OptionParser.new { |o| o.on("-n NAME", "borrow this example's keywords") { |v| borrow = v } }.parse!(argv)
    spec_file, program = argv
    raise ArgumentError, "want: rake 'spec:ask[<spec_file> <program.rb>]'" unless spec_file && program

    kwargs = { path: Zr::Reader.path_for(spec_file) }
    if borrow
      from = Zr::Reader.read(spec_file).find { |e| e.name == borrow }
      raise ArgumentError, "no example named #{borrow.inspect} in #{spec_file}" unless from

      kwargs = from.kwargs
    end
    example = Zr::Reader::Example.new(name: "ask", source: File.read(program), kwargs: kwargs, want: {})
    answer = Oracle.ask(example)
    raise "ruby did not finish" unless answer

    puts SpecAsk.assertion(answer)
  end
end
