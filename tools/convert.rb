# frozen_string_literal: true

# A corpus case becomes a spec example: the program inlined, and the
# answer ruby recorded lifted into an assertion. Nothing here asks ruby
# anything -- the trailer is already ruby's word -- so a literal this
# writes still traces to ruby 4.0.6. `rake oracle:verify` re-checks them.
#
#   ruby tools/convert.rb --out test/spec/core/string/upcase_test.rb \
#     --describe "String#upcase" <case path>...
#   ruby tools/convert.rb --plan test/core/string        # what would convert
#
# A case this cannot express is refused by name rather than converted
# into a weaker test. `--plan` prints the refusals and converts nothing.

require "fileutils"
require "optparse"
require_relative "../test/support/harness/case"

module Convert
  ROOT = File.expand_path("..", __dir__)

  # The heredoc terminators to try, in order. A program holding a line
  # that is one of these takes the next.
  TERMINATORS = %w[RUBY PROGRAM ZE0_SOURCE].freeze

  # Directives that map straight onto a `ze0` keyword.
  PASSED = { args: :argv, env: :env, stdin: :stdin }.freeze

  Example = Struct.new(:name, :source, :expected, :directives, :path, :files, keyword_init: true)

  module_function

  # `[example, nil]`, or `[nil, why]` for a case this cannot express.
  def read(rb)
    kase = Ze0::Harness::Case.read(rb)
    return [nil, "no recording"] unless kase.recorded?

    d = kase.directives
    return [nil, "`#@ backend: jit` wants the compiler in process"] if d.backend
    return [nil, "`#@ gccheck:` is a sidecar census"] if d.gccheck
    return [nil, "`#@ zeo:` names CLI flags no example has"] unless d.zeo.empty?
    return [nil, "references DATA"] if kase.program.match?(/\bDATA\b/)

    source = strip(kase.program)
    return [nil, "the program is not UTF-8"] unless source.valid_encoding?
    return [nil, "every line is a directive or a comment"] if source.strip.empty?
    return [nil, "no heredoc terminator is free"] unless terminator(source)

    files = files_for(rb)
    rel = rb.delete_prefix("#{ROOT}/test/")
    # A key that climbs out of the program's own directory only lands
    # where the program looks for it if the program sits where it sat.
    path = path_for(rb, kase) || (rel if files.each_key.any? { |k| k.start_with?("..") })

    [Example.new(name: name_of(rb), source: source, expected: expected(kase, rb),
                 directives: d, path: path, files: files), nil]
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
    program.each_line.reject { |line| line.start_with?("#@") }.join.force_encoding(Encoding::UTF_8)
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
  def files_for(rb)
    dir = File.dirname(rb)
    test = File.join(ROOT, "test")
    out = {}
    # The documented rule first: a directory named after the program
    # holds that program's own files, whether or not the source spells
    # the name plainly -- `autoload :C, "#{__dir__}/x/y"` does not.
    beside = rb.sub(/\.rb\z/, "")
    if File.directory?(beside)
      Dir[File.join(beside, "**/*")].select { |f| File.file?(f) }.each { |f| out[relative(f, dir)] = File.binread(f) }
    end
    queue = [rb]
    until queue.empty?
      file = queue.shift
      references(File.binread(file)).each do |ref|
        target = resolve(ref, File.dirname(file), test)
        next if target.nil? || target == rb

        if File.directory?(target)
          Dir[File.join(target, "**/*")].select { |f| File.file?(f) }.each do |f|
            out[relative(f, dir)] ||= File.binread(f)
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

    [from, test].each do |root|
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
    out << "skip \"runs only on #{d.only.join(", ")}\" unless #{d.only.inspect}.include?(Ze0::Spec.platform)" if d.only
    d.needs.each { |need| out << "skip \"needs #{need}\" unless Ze0::Spec.need?(#{need.inspect})" }
    out
  end

  def example(ex)
    want = ex.expected
    plain = want.stderr.empty? && want.code == 0 && want.signal.nil?
    body = plain && guards(ex).empty? && !heredoc?(want.stdout) ? compact(ex) : full(ex)
    ["  it #{ex.name.inspect} do", *body.map { |l| l.empty? ? l : "  #{l}" }, "  end"]
  end

  # One assertion, with the program trailing it: the shape 97 cases in a
  # hundred take.
  def compact(ex)
    t = terminator(ex.source)
    call = ["<<~'#{t}'", *keywords(ex)].join(", ")
    ["  _(ze0(#{call}).stdout).must_equal #{literal(ex.expected.stdout)}",
     *ex.source.each_line.map { |l| l.chomp.empty? ? "" : "    #{l.chomp}" }, "  #{t}"]
  end

  # Arrange, act, assert: the program, then what it is held to.
  def full(ex)
    t = terminator(ex.source)
    want = ex.expected
    call = ["<<~'#{t}'", *keywords(ex)].join(", ")
    out = guards(ex).map { |g| "  #{g}" }
    out << "" unless out.empty?
    out << "  result = ze0(#{call})"
    out.concat(ex.source.each_line.map { |l| l.chomp.empty? ? "" : "    #{l.chomp}" })
    out << "  #{t}" << ""
    out << if heredoc?(want.stdout)
             "  _(result.stdout).must_equal <<~'OUT'"
           else
             "  _(result.stdout).must_equal #{literal(want.stdout)}"
           end
    out.concat(heredoc(want.stdout, "  ")) if heredoc?(want.stdout)
    unless want.stderr.empty?
      if heredoc?(want.stderr)
        out << "  _(result.stderr).must_equal <<~'OUT'"
        out.concat(heredoc(want.stderr, "  "))
      else
        out << "  _(result.stderr).must_equal #{literal(want.stderr)}"
      end
    end
    out << "  _(result.status).must_equal #{want.code}" if want.code && want.code != 0
    out << "  _(result.signal).must_equal #{want.signal}" if want.signal
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
