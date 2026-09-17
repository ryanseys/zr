# frozen_string_literal: true

# A corpus case becomes a spec example: the program inlined, and the
# answer ruby recorded lifted into an assertion. Nothing here asks ruby
# anything -- the trailer is already ruby's word -- so a literal this
# writes still traces to ruby 4.0.6. `rake oracle:verify` re-checks them.
#
#   ruby tools/convert.rb --area core/string             # writes test/spec/core/string/
#   ruby tools/convert.rb --out test/spec/core/string/frozen_test.rb \
#     --describe "String: frozen literals" <case path>...
#   ruby tools/convert.rb --plan test/core/string        # what would convert
#
# A case this cannot express is refused by name rather than converted
# into a weaker test. `--plan` prints the refusals and converts nothing.

require "fileutils"
require "optparse"
require_relative "../test/support/harness/case"
require_relative "subjects"

module Convert
  ROOT = File.expand_path("..", __dir__)

  # The heredoc terminators to try, in order. A program holding a line
  # that is one of these takes the next.
  TERMINATORS = %w[RUBY PROGRAM ZE0_SOURCE].freeze

  # Directives that map straight onto a `ze0` keyword.
  PASSED = { args: :argv, env: :env, stdin: :stdin }.freeze

  Example = Struct.new(:name, :source, :expected, :directives, :path, :files, :stdin, keyword_init: true)

  module_function

  # `[example, nil]`, or `[nil, why]` for a case this cannot express.
  def read(rb)
    kase = Ze0::Harness::Case.read(rb)
    return [nil, "no recording"] unless kase.recorded?

    d = kase.directives
    return [nil, "`#@ backend: jit` wants the compiler in process"] if d.backend
    return [nil, "`#@ zeo:` names CLI flags no example has"] unless d.zeo.empty?
    return [nil, "references DATA"] if kase.program.match?(/\bDATA\b/)

    source = strip(kase.program)
    return [nil, "the program is not UTF-8"] unless source.valid_encoding?
    return [nil, "every line is a directive or a comment"] if source.strip.empty?
    return [nil, "no heredoc terminator is free"] unless terminator(source)

    files = files_for(rb, d)
    rel = rb.delete_prefix("#{ROOT}/test/")
    # A key that climbs out of the program's own directory only lands
    # where the program looks for it if the program sits where it sat.
    # A file the program is handed, or one above its own directory, only
    # lands where the program looks for it if the program sits where it
    # sat.
    named = files.each_key.any? { |k| k.start_with?("..") } ||
            d.args.any? { |arg| resolve(arg, File.join(ROOT, "test"), File.join(ROOT, "test")) }
    path = path_for(rb, kase) || (rel if named)

    stdin = d.stdin && File.binread(File.join(File.dirname(rb), d.stdin))

    [Example.new(name: name_of(rb), source: source, expected: expected(kase, rb),
                 directives: d, path: path, files: files, stdin: stdin), nil]
  end

  # What an example asserts. `ze0` answers a scrubbed result -- an
  # object address and a thread id are the program's own each run -- so
  # the literal is scrubbed the same way, and the two can be equal.
  def expected(kase, rb)
    want = kase.answer
    dir = File.dirname(rb)
    Ze0::Harness::Answer.new(Ze0::Harness::Normalize.bytes(want.stdout, rb, dir),
                             Ze0::Harness::Normalize.bytes(want.stderr, rb, dir),
                             want.code, want.signal)
  end

  # The directive lines go: an example carries them as arguments. The
  # bytes come back as text, since a spec file is Ruby source and a
  # program that is not UTF-8 cannot be inlined into one.
  def strip(program)
    # Blanked, not dropped: a program's own backtraces name its line
    # numbers, and dropping two directive lines moves every line under
    # them.
    program.each_line.map { |line| line.start_with?("#@") ? "\n" : line }.join.force_encoding(Encoding::UTF_8)
  end

  # An example reads as a sentence, which is what the file name already
  # is: `a_frozen_string_is_not_duped.rb`.
  def name_of(rb) = File.basename(rb, ".rb").tr("_", " ")

  # The name the program must answer to, for the one case in forty whose
  # own answer carries its path. Every other example takes the default.
  def path_for(rb, kase)
    rel = rb.delete_prefix("#{ROOT}/test/")
    text = kase.answer.stdout + kase.answer.stderr
    rel if text.include?(rel) || text.include?(File.basename(rb))
  end

  # The files the program reaches for, keyed by the name it reaches for
  # them by. A directory beside the program usually holds them, but not
  # always -- `frozen_string_literal_per_file_rev.rb` requires out of
  # `frozen_string_literal_per_file/`, named after its neighbour -- so
  # what the source actually names is what counts, followed as far as it
  # goes. `test/` is the other root, since that is where a program runs
  # and where `fixtures/` answers from.
  def files_for(rb, directives)
    dir = File.dirname(rb)
    test = File.join(ROOT, "test")
    out = {}
    # The documented rule first: a directory named after the program
    # holds that program's own files, whether or not the source spells
    # the name plainly -- `autoload :C, "#{__dir__}/x/y"` does not.
    beside = rb.sub(/\.rb\z/, "")
    if File.directory?(beside)
      Dir[File.join(beside, "**/*")].each { |f| out[relative(f, dir)] = contents(f) if File.file?(f) || File.symlink?(f) }
    end
    # `#@ args: core/io/argf_input.txt` names a file from the directory
    # the program runs in. The source never spells it, so the directives
    # are read too.
    directives.args.each do |arg|
      target = resolve(arg, test, test)
      next unless target && File.file?(target)

      # The key is where the program's own directory would find it, and
      # the program keeps its own path so that the two agree.
      out[relative(target, dir)] ||= File.binread(target)
    end

    queue = [rb]
    until queue.empty?
      file = queue.shift
      references(File.binread(file)).each do |ref|
        target = resolve(ref, File.dirname(file), test)
        next if target.nil? || target == rb

        if File.directory?(target)
          Dir[File.join(target, "**/*")].each do |f|
            out[relative(f, dir)] ||= contents(f) if File.file?(f) || File.symlink?(f)
          end
          next
        end

        key = relative(target, dir)
        next if out.key?(key)

        out[key] = File.binread(target)
        queue << target if target.end_with?(".rb")
      end
    end
    out
  end

  # The names a program could be reaching for: what it requires, and any
  # quoted word that looks like a path.
  def references(source)
    text = source.dup.force_encoding(Encoding::UTF_8)
    return [] unless text.valid_encoding?

    plain = text.gsub(/\#\{[^}]*\}/, "\x00")
    (plain.scan(/require(?:_relative)?\s+["']([^"']+)["']/).flatten +
      plain.scan(/["']([^"'\n]*\/[\w.\-]+|[\w.\-]+\.(?:rb|txt|bin|json|yml|stdin))["']/).flatten)
      .map { |ref| ref.split("\x00").last.to_s.delete_prefix("/") }
      .reject(&:empty?)
  end

  # Where a name lands: beside the file that named it, or under `test/`,
  # with `.rb` added as `require` would.
  def resolve(ref, from, test)
    return nil if ref.start_with?("/")

    # A bare name is a load-path lookup, not a path: `require "spec"`
    # names a file the program's own directory puts on the path, and
    # never `test/spec`. Only a name with a `/` in it is tried there.
    roots = ref.include?("/") ? [from, test] : [from]
    roots.each do |root|
      base = File.expand_path(ref, root)
      # `..` is allowed; what is not allowed is leaving `test/`.
      next unless base.start_with?("#{test}/")

      [base, "#{base}.rb"].each { |c| return c if File.file?(c) || File.directory?(c) }
    end
    nil
  end

  # `target` as `dir` would name it, `..` and all.
  def relative(target, dir)
    require "pathname"
    Pathname.new(target).relative_path_from(Pathname.new(dir)).to_s
  end

  # A file's bytes, or where a link points: `Dir[]` does not follow a
  # link that points at a directory, and a program that asks whether two
  # paths are one file needs the link and not a copy.
  def contents(path)
    File.symlink?(path) ? { symlink: File.readlink(path) } : File.binread(path)
  end

  def terminator(source)
    TERMINATORS.find { |t| source.each_line.none? { |line| line.strip == t } }
  end

  # `"AB\n"` where the bytes are text, and the bytes where they are not.
  def literal(bytes)
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    text.valid_encoding? ? text.inspect : "#{bytes.inspect}.b"
  end

  # Whether several lines of expected output can be written as a heredoc,
  # which reads as the program's own output rather than as one long
  # escape. `<<~` takes the common indentation off, so a line that leans
  # on its own leading space, a body that does not end in a newline, and
  # a line that would close the heredoc all keep the escaped form.
  def heredoc?(bytes)
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    return false unless text.valid_encoding?
    return false unless text.end_with?("\n") && text.lines.size > 1

    text.lines.none? { |line| line.start_with?(" ", "\t") || line.match?(/[ \t]\n\z/) || TERMINATORS.include?(line.chomp) }
  end

  # The expected output as a heredoc body, indented under `at`.
  def heredoc(bytes, at)
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    [*text.lines.map { |l| l.chomp.empty? ? "" : "#{at}  #{l.chomp}" }, "#{at}OUT"]
  end

  def keywords(example)
    out = []
    d = example.directives
    out << "path: #{example.path.inspect}" if example.path
    out << "stdin: #{literal(example.stdin)}" if example.stdin
    out << "argv: #{d.args.inspect}" unless d.args.empty?
    out << "env: #{d.env.inspect}" unless d.env.empty?
    out << "env: #{d.zeo_env.inspect}" unless d.zeo_env.empty?
    out << "files: #{example.files.inspect}" unless example.files.empty?
    out
  end

  # The guards a directive draws: a platform the program does not run on,
  # a library the machine may lack.
  def guards(example)
    d = example.directives
    out = []
    # A gap says what it is waiting on and stays where it belongs; the
    # day ze0 answers it, the line comes off.
    out << "skip #{d.skip.inspect}" if d.skip
    out << "skip \"runs only on #{d.only.join(", ")}\" unless #{d.only.inspect}.include?(Ze0::Spec.platform)" if d.only
    d.needs.each { |need| out << "skip \"needs #{need}\" unless Ze0::Spec.need?(#{need.inspect})" }
    out
  end

  def example(ex)
    body = compact?(ex) ? compact(ex) : full(ex)
    ["  it #{ex.name.inspect} do", *body.map { |l| l.empty? ? l : "  #{l}" }, "  end"]
  end

  # One line holds the whole example when there is nothing to guard and
  # the answer is short enough to read at the end of it.
  def compact?(ex) = guards(ex).empty? && !heredoc?(ex.expected.stdout)

  # What `must_answer` is told beyond stdout. Each is the recording's
  # own word: an absent `#@ stderr` means stderr is empty, and an
  # absent `#@ exit` means the status is zero, so the defaults say what
  # the trailer said.
  def answer_options(ex)
    want = ex.expected
    out = []
    out << "stderr: #{literal(want.stderr)}" unless want.stderr.empty?
    # A process a signal ended carries no status at all, so `status:` is
    # nil there and not zero.
    out << "status: #{want.code.inspect}" unless want.code == 0
    out << "signal: #{want.signal}" if want.signal
    out
  end

  def compact(ex)
    t = terminator(ex.source)
    call = ["<<~'#{t}'", *keywords(ex)].join(", ")
    want = [literal(ex.expected.stdout), *answer_options(ex)].join(", ")
    ["  _(ze0(#{call})).must_answer #{want}",
     *ex.source.each_line.map { |l| l.chomp.empty? ? "" : "    #{l.chomp}" }, "  #{t}"]
  end

  # Arrange, act, assert: the program, then the whole answer it is held
  # to, written as the program's own output where that reads better than
  # one long escape.
  def full(ex)
    t = terminator(ex.source)
    want = ex.expected
    call = ["<<~'#{t}'", *keywords(ex)].join(", ")
    out = guards(ex).map { |g| "  #{g}" }
    out << "" unless out.empty?
    out << "  result = ze0(#{call})"
    out.concat(ex.source.each_line.map { |l| l.chomp.empty? ? "" : "    #{l.chomp}" })
    out << "  #{t}" << ""

    options = answer_options(ex)
    if heredoc?(want.stdout)
      out << "  _(result).must_answer #{["<<~'OUT'", *options].join(", ")}"
      out.concat(heredoc(want.stdout, "  "))
    else
      out << "  _(result).must_answer #{[literal(want.stdout), *options].join(", ")}"
    end
    out
  end

  def file(describe, examples)
    lines = ["# frozen_string_literal: true", "", 'require "spec_helper"', "",
             "describe #{describe.inspect} do"]
    examples.each_with_index do |ex, i|
      lines << "" unless i.zero?
      lines.concat(example(ex))
    end
    lines << "end" << ""
    lines.join("\n")
  end
end

# The command, when this file is the one ruby was given.
if $PROGRAM_NAME == __FILE__
  # An area at a time: every case planned, grouped, and written to the
# file its subject names.
def convert_area(area)
  dir = File.join(Convert::ROOT, "test", area)
  abort("convert: no area #{area}") unless File.directory?(dir)

  cases = Dir[File.join(dir, "*.rb")].sort.filter_map do |rb|
    kase = (Ze0::Harness::Case.read(rb) rescue next)
    kase.recorded? ? [rb, kase.program] : nil
  end
  plan = Subjects.plan(area, cases)

  written = 0
  refused = []
  plan.group_by { |_, (path, describe, _)| [path, describe] }.each do |(path, describe), rows|
    examples = rows.filter_map do |rb, (_, _, drop)|
      ex, why = Convert.read(rb)
      unless ex
        refused << [rb, why]
        next
      end

      ex.name = Subjects.name_for(rb, drop)
      ex
    end
    next if examples.empty?

    out = File.join(Convert::ROOT, "test/spec", path)
    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, Convert.file(describe, examples.sort_by(&:name)))
    written += 1
  end
  refused.each { |rb, why| warn "refused #{rb.delete_prefix("#{Convert::ROOT}/")}: #{why}" }
  puts format("%-24s %4d example(s) -> %2d file(s), %d refused", area, plan.size - refused.size, written, refused.size)
  refused.size
end

if ARGV.first == "--area"
  ARGV.shift
  abort("usage: ruby tools/convert.rb --area <area>...") if ARGV.empty?
  # A refused case is named, not fatal: it stays a corpus program and
  # the end-to-end tier carries it.
  ARGV.each { |area| convert_area(area) }
  exit 0
end

out = nil
  describe = nil
  plan = false
  OptionParser.new do |o|
    o.on("--out PATH") { |v| out = v }
    o.on("--describe TEXT") { |v| describe = v }
    o.on("--plan") { plan = true }
  end.parse!(ARGV)

  cases = ARGV.flat_map { |a| File.directory?(a) ? Dir[File.join(a, "*.rb")].sort : [a] }
  abort "usage: ruby tools/convert.rb [--plan] [--out PATH --describe TEXT] <case or dir>..." if cases.empty?

  examples = []
  refused = []
  cases.each do |rb|
    ex, why = Convert.read(File.expand_path(rb))
    ex ? examples << ex : refused << [rb, why]
  end

  refused.each { |rb, why| warn "refused #{rb.delete_prefix("#{Convert::ROOT}/")}: #{why}" }
  puts "#{examples.size} convertible, #{refused.size} refused"
  exit(refused.empty? ? 0 : 1) if plan

  abort "convert: --out and --describe name where the examples go" unless out && describe
  FileUtils.mkdir_p(File.dirname(out))
  File.write(out, Convert.file(describe, examples))
  puts "wrote #{out} (#{examples.size} example(s))"
  exit(refused.empty? ? 0 : 1)
end
