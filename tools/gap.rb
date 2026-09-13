# frozen_string_literal: true

# Moves corpus programs ze0 does not get right into test/gaps/, so every
# other suite holds only programs that match and a sweep of them reads as
# a pass, while the gaps wait together to be worked through.
#
#   ruby tools/gap.rb core/string/a_case.rb ...   move these
#   ruby tools/gap.rb --sweep tmp/sweep.txt        move every row a sweep listed
#
# A path is taken relative to test/. A program keeps its file name; one
# whose name test/gaps/ already holds takes its topic as a prefix. A
# directory beside it that carries its name holds its helpers, and goes
# with it.
#
# A move is more than a rename. A recording can name the program's own
# path, a `require_relative` or a `#@ stdin:` names a file beside it, and
# `__dir__` points somewhere else afterwards. So the recording's own path
# is rewritten to the new one, and so is every relative path the program
# names by a string literal. Then ruby -- the only oracle -- runs the
# program where it was and where it is going. The move stands only if the
# two answers are the same once the path is; otherwise the program stays
# where it is and the reason is printed.
#
# `test/gaps/ORIGINS.tsv` keeps where each gap came from, so the day one
# matches it can go back to its topic.

require "fileutils"
require "pathname"
require "rbconfig"
require "set"
require_relative "../lib/ze0/harness/sweep"

module Gap
  TEST = File.expand_path("../test", __dir__)
  GAPS = File.join(TEST, "gaps")
  ORIGINS = File.join(GAPS, "ORIGINS.tsv")
  END_MARK = /^__END__\n/

  # A file named by a literal relative to the program's own directory:
  # `require_relative "x"`, and `File.expand_path("x", __dir__)`.
  RELATIVE = /(?<head>require_relative[ (]*|File\.expand_path\(\s*)(?<quote>["'])(?<path>[^"'#]+)\k<quote>(?<tail>\s*,\s*__dir__\s*\))?/

  Move = Struct.new(:from, :to, :why) do
    def moved? = why.nil?
  end

  module_function

  def run(paths)
    sweep = Ze0::Harness::Sweep.new(File.dirname(TEST))
    taken = Dir.children(GAPS).to_set
    paths.map do |rel|
      move = one(rel, taken, sweep)
      puts move.moved? ? "moved   #{move.from} -> #{move.to}" : "stays   #{move.from}: #{move.why}"
      move
    end
  end

  def one(rel, taken, sweep)
    return Move.new(rel, rel, "already a gap") if rel.start_with?("gaps/")
    return Move.new(rel, nil, "no such program") unless File.file?(File.join(TEST, rel))

    name = File.basename(rel)
    name = "#{File.dirname(rel).tr("/", "_")}_#{name}" if taken.include?(name) || taken.include?(stem(name))
    to = "gaps/#{name}"
    source, trailer = File.binread(File.join(TEST, rel)).split(END_MARK, 2)
    return Move.new(rel, to, "no recording") unless trailer

    before = answer(rel, sweep)
    helpers = [helpers_of(rel), helpers_of(to)]
    FileUtils.mv(*helpers) if File.directory?(helpers[0])
    File.binwrite(File.join(TEST, to), "#{relocated(source, rel, to, helpers)}__END__\n#{trailer.gsub(rel, to)}")
    why = difference(before, rel, to, sweep)
    if why
      File.delete(File.join(TEST, to))
      FileUtils.mv(*helpers.reverse) if File.directory?(helpers[1])
      return Move.new(rel, to, why)
    end

    File.delete(File.join(TEST, rel))
    taken << name << stem(name)
    File.open(ORIGINS, "a") { |f| f.puts "#{to}\t#{rel}" }
    Move.new(rel, to, nil)
  end

  def stem(name) = name.delete_suffix(".rb")

  # The directory of helpers a program at `rel` keeps beside itself.
  def helpers_of(rel) = File.join(TEST, stem(rel))

  # Every literal relative path the program names, spelled from where it
  # is going; a path into its helpers follows them. A path that named
  # nothing where the program was is left as it is: it was never a file,
  # and ruby says so either way.
  def relocated(source, from, to, (old_helpers, new_helpers))
    old_dir = File.dirname(File.join(TEST, from))
    new_dir = File.dirname(File.join(TEST, to))
    respell = lambda do |path|
      # `__dir__`'s `x` and `require_relative`'s both name a place from
      # the program's directory.
      target = File.expand_path(path, old_dir)
      target = target.sub(old_helpers, new_helpers) if target == old_helpers || target.start_with?("#{old_helpers}/")
      exists = [target, "#{target}.rb"].any? { |t| File.exist?(t) }
      exists ? relative(target, new_dir) : path
    end
    source
      .gsub(RELATIVE) do |text|
        head, quote, path, tail = $~.values_at(:head, :quote, :path, :tail)
        # `File.expand_path` resolves against `__dir__` only when told to.
        next text if head.start_with?("File") && tail.nil?

        "#{head}#{quote}#{respell.call(path)}#{quote}#{tail}"
      end
      .gsub(/^(#@ stdin:\s*)(\S+)/) do
        head, path = $1, $2
        "#{head}#{respell.call(path)}"
      end
  end

  def relative(target, dir)
    Pathname(target).relative_path_from(Pathname(dir)).to_s
  end

  # Why ruby answers differently at `to` than it did at `from`, or nil.
  # The answer from `from` has its path spelled as `to` first, which is
  # exactly the change the recording was given.
  def difference(before, from, to, sweep)
    after = answer(to, sweep)
    return "ruby ran past #{Ze0::Harness::Sweep::LIMIT}s" if before.code == :timeout || after.code == :timeout

    %i[stdout stderr].each { |s| before[s] = before[s].gsub(from, to) }
    return nil if before == after

    "ruby answers differently there: #{sweep.diff(before, after)}"
  end

  def answer(rel, sweep)
    path = File.join(TEST, rel)
    kase = Ze0::Harness::Case.read(path)
    d = kase.directives
    stdin = d.stdin && File.binread(File.expand_path(d.stdin, File.dirname(path)))
    out = sweep.bounded([RbConfig.ruby, *d.ruby, rel, *d.args], TEST, stdin, d.env)
    Ze0::Harness::Normalize.answer(out, path, TEST)
  end

  # The programs a sweep's row file lists: `bucket test/<path>` lines.
  def rows(file)
    File.readlines(file, chomp: true).filter_map do |line|
      bucket, path = line.split(" ", 2)
      path.delete_prefix("test/") if path && %w[refused backend diverged crashed timeout].include?(bucket)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  args = ARGV.dup
  abort "usage: ruby tools/gap.rb <path>... | --sweep <rows file>" if args.empty?
  paths = args.first == "--sweep" ? Gap.rows(args.fetch(1)) : args.map { |a| a.delete_prefix("test/") }
  moves = Gap.run(paths)
  puts "#{moves.count(&:moved?)} moved, #{moves.count { |m| !m.moved? }} stayed"
end
