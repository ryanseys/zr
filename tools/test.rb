# Runs corpus programs the way `ze0 test` runs them, and says as much
# about each run as a person fixing the program needs: what was built
# and how long it took, what the binary answered, and every line where
# that answer parts from ruby's recording.
#
#   ruby tools/test.rb core/io/a_stream_reads_what_it_holds.rb
#   ruby tools/test.rb core/io core/file            # a net, in parallel
#   ruby tools/test.rb core/range --keep --verbose
#   ruby tools/test.rb ze0 --target wasm32-wasi
#
# A path names a case under test/, a directory of them, or any part of a
# case's name. One case prints in full; a net prints a line for each and
# the whole of every program that did not match. The exit status is 0
# when every case matched.
#
# Every row but the matched ones is written to tmp/test-rows.txt, in the
# shape `ze0 test` writes tmp/sweep.txt, so the two compare, with the
# path of the case's whole report under it. The report
# (tmp/test-report/<case>.txt) holds every differing line, the build's
# output and the binary's own stdout and stderr, so a failure never
# needs a second run to read; the binary and its output stay in
# tmp/test-failed/<case>/. A case's report and binary go when it runs
# again.
require "etc"
require "fileutils"
require "rbconfig"
require "tmpdir"
require_relative "../lib/ze0/harness/case"
require_relative "../lib/ze0/harness/child"
require_relative "../lib/ze0/harness/runner"

ROOT = File.expand_path("..", __dir__)
TESTS = File.join(ROOT, "test")

options = { gc: "plain", timeout: 60, keep: false, verbose: false, diff: 20, jobs: nil, target: Ze0::Target.default }
filters = []
argv = ARGV.dup
until argv.empty?
  word = argv.shift
  case word
  when "--gc" then options[word.delete_prefix("--").to_sym] = argv.shift
  when "--timeout", "--diff", "--jobs" then options[word.delete_prefix("--").to_sym] = Integer(argv.shift)
  when "-j" then options[:jobs] = Integer(argv.shift)
  when "--target" then options[:target] = Ze0::Target.fetch(argv.shift.to_s) || abort("no such target; `ze0 targets` names them")
  when "--keep" then options[:keep] = true
  when "--verbose", "-v" then options[:verbose] = true
  when "-h", "--help" then abort File.read(__FILE__).lines.grep(/\A#/).join
  else filters << word
  end
end
abort "usage: ruby tools/test.rb <case path>... [--jobs N] [--gc plain|stress] [--keep] [--verbose] [--diff N] [--timeout N] [--target <triple>]" if filters.empty?
RUNNER = Ze0::Harness::Runner.new(ROOT, options[:target])
abort RUNNER.refusal if RUNNER.refusal

Row = Struct.new(:rel, :verdict, :lines, :build, :run, :why, :report)
REPORTS = File.join(ROOT, "tmp", "test-report")
FAILED = File.join(ROOT, "tmp", "test-failed")

# Every recorded program a filter names: a path, a directory, or any
# part of one, as `ze0 test` reads its filters.
def select(filters)
  every = Dir[File.join(TESTS, "*", "*.rb"), File.join(TESTS, "*", "*", "*.rb")].sort
  filters.flat_map do |filter|
    want = File.expand_path(filter.delete_prefix("./"), filter.start_with?("/") ? "/" : TESTS)
    found = every.select { |rb| rb == want || rb.start_with?("#{want}/") || rb.include?(filter.delete_prefix("test/")) }
    abort "no program matches #{filter.inspect}" if found.empty?

    found
  end.uniq
end

# A child bounded by the time limit and by `megabytes`, and the time it
# took.
def bounded(argv, cwd, stdin, env, limit, megabytes)
  Ze0::Harness::Child.run(argv, cwd: cwd, stdin: stdin, env: env, seconds: limit, megabytes: megabytes)
end

# Where two long lines first part, with the text around it on both
# sides; nil for short lines, which read whole.
def apart_at(want, got)
  return nil unless want && got

  want = want.b
  got = got.b
  return nil if [want.bytesize, got.bytesize].max <= 100

  i = 0
  i += 1 while i < want.bytesize && i < got.bytesize && want.getbyte(i) == got.getbyte(i)
  from = [i - 30, 0].max
  format("           col %d: want %s | got %s", i + 1, want.byteslice(from, 70).inspect, got.byteslice(from, 70).inspect)
end

# Every line where the two answers part, numbered from 1, the recording
# first, at most `limit` of them (nil for all). A stream that matches
# says so in one line.
def stream_lines(what, want, got, limit)
  want_lines = want.lines
  got_lines = got.lines
  return [format("  %-10s %d line(s), the same", what, want_lines.size), 0] if want_lines == got_lines

  out = [format("  %-10s want %d line(s), got %d", what, want_lines.size, got_lines.size)]
  apart = 0
  [want_lines.size, got_lines.size].max.times do |i|
    next if want_lines[i] == got_lines[i]

    apart += 1
    next if limit && apart > limit

    out << format("    %4d - %s", i + 1, want_lines[i] ? want_lines[i].chomp.inspect : "(no line)")
    out << format("    %4d + %s", i + 1, got_lines[i] ? got_lines[i].chomp.inspect : "(no line)")
    at = apart_at(want_lines[i]&.chomp, got_lines[i]&.chomp)
    out << at if at
  end
  out << "    ... #{apart - limit} more differing line(s) in the report" if limit && apart > limit
  [out, apart]
end

# The bound a child went past, in words, or nil.
def bound(answer, options)
  case answer.code
  when :timeout then "ran past #{options[:timeout]}s"
  when :memory then "held more memory than its bound (ZE0_BUILD_MB, ZE0_RUN_MB)"
  end
end

# The case's whole report, written where the row names it, and the
# binary with what it printed kept beside it (nil when the build made
# none).
def keep_failure(row, full, bin, ran)
  report = File.join(REPORTS, "#{row.rel}.txt")
  FileUtils.mkdir_p(File.dirname(report))
  File.write(report, ["case #{row.rel}", *full, ""].join("\n"))
  if bin && File.exist?(bin)
    dir = File.join(FAILED, row.rel.delete_suffix(".rb"))
    FileUtils.mkdir_p(dir)
    FileUtils.cp(bin, File.join(dir, "p"))
    if ran
      File.binwrite(File.join(dir, "stdout"), ran.stdout)
      File.binwrite(File.join(dir, "stderr"), ran.stderr)
    end
    File.open(report, "a") { |f| f.puts "  binary     #{File.join(dir, "p")}" }
  end
  row.report = report
  row
end

# One program: built, run, and compared. Its whole report comes back as
# lines, so that programs running side by side do not interleave.
def one(rb, options)
  rel = rb.delete_prefix("#{TESTS}/")
  FileUtils.rm_f(File.join(REPORTS, "#{rel}.txt"))
  FileUtils.rm_rf(File.join(FAILED, rel.delete_suffix(".rb")))
  kase = Ze0::Harness::Case.read(rb)
  directives = kase.directives
  lines = [format("  %-10s args=%s env=%s stdin=%s%s", "program", directives.args.inspect, directives.env.inspect,
                  directives.stdin || "-", directives.only ? " only=#{directives.only.join(",")}" : "")]
  unless kase.recorded?
    lines << "  #{"skipped".ljust(10)} no recording: run `ruby tools/record.rb #{rel}` first"
    return Row.new(rel, :skipped, lines, 0, 0, "no recording")
  end
  unless kase.runs_on?(RUNNER.platform)
    lines << "  #{"skipped".ljust(10)} only on #{directives.only.join(", ")}"
    return Row.new(rel, :skipped, lines, 0, 0, "only #{directives.only.join(", ")}")
  end

  work = Dir.mktmpdir("ze0-tool-test-")
  keep = options[:keep]
  bin = File.join(work, "p")
  build = RUNNER.build_argv(rel, bin)
  built, build_seconds = bounded(build, TESTS, nil, RUNNER.build_env, options[:timeout], Ze0::Harness::Child.build_mb(directives))
  lines << format("  %-10s %5.1fs %s", "build", build_seconds, built.code == 0 ? "ok" : "FAILED (#{bound(built, options) || built.status})")
  lines << "  #{"command".ljust(10)} #{build.join(" ")}"
  if built.code != 0 || options[:verbose]
    [built.stdout, built.stderr].each { |text| text.each_line { |line| lines << "    #{line.chomp}" } }
  end
  if built.code != 0
    lines << "  #{"binary".ljust(10)} #{work} (kept)" if keep
    full = lines.dup
    [built.stdout, built.stderr].each { |text| text.each_line { |line| full << "    #{line.chomp}" } } unless options[:verbose]
    FileUtils.remove_entry(work) unless keep
    why = bound(built, options) || (built.stderr.empty? ? built.stdout : built.stderr).lines.first.to_s.strip
    return keep_failure(Row.new(rel, built.code == 3 ? :refused : :backend, lines, build_seconds, 0, why), full, nil, nil)
  end

  stdin = directives.stdin && File.binread(File.join(File.dirname(rb), directives.stdin))
  env = directives.env.merge(directives.zeo_env)
  env["ZR_GC_STRESS"] = "1" if options[:gc] == "stress"
  argv, run_env = RUNNER.run(bin, directives.args, env)
  ran, run_seconds = bounded(argv, TESTS, stdin, run_env, options[:timeout], Ze0::Harness::Child::RUN_MB)
  lines << format("  %-10s %5.1fs %s", "run", run_seconds, bound(ran, options) || ran.status)
  lines << "  #{"binary".ljust(10)} #{bin}" if keep
  if ran.code == :timeout || ran.code == :memory
    row = Row.new(rel, ran.code == :timeout ? :timeout : :crashed, lines, build_seconds, run_seconds, bound(ran, options))
    keep_failure(row, lines, bin, ran)
    FileUtils.remove_entry(work) unless keep
    return row
  end

  expected = Ze0::Harness::Normalize.answer(kase.expected(RUNNER.platform), rb, TESTS)
  actual = Ze0::Harness::Normalize.answer(ran, rb, TESTS)
  lines << format("  %-10s %s", "status",
                  expected.status == actual.status ? "#{actual.status}, the same" : "want #{expected.status}, got #{actual.status}")
  apart = 0
  full = lines.dup
  %i[stdout stderr].each do |what|
    said, n = stream_lines(what, expected[what], actual[what], options[:diff])
    lines.concat(Array(said))
    full.concat(Array(stream_lines(what, expected[what], actual[what], nil)[0]))
    apart += n
  end
  if options[:verbose]
    %i[stdout stderr].each do |what|
      next if actual[what].empty?

      lines << "  #{what} in full:"
      actual[what].each_line { |line| lines << "    #{line.chomp}" }
    end
  end
  stop = actual.stderr[/^(?:ze0: |.*?:in '[^']*': )?(.* is not implemented yet)(?: \((?:NotImplementedError|LoadError)\))?$/, 1]
  verdict = if expected == actual then :matched
            elsif stop then :refused
            elsif (actual.signal || RUNNER.trapped?(actual)) && !expected.signal then :crashed
            else :diverged
            end
  tail = [format("  %-10s %s%s", "verdict", verdict, stop && verdict == :refused ? ": #{stop}" : "")]
  tail << format("  %-10s %d line(s) apart", "apart", apart) if verdict == :diverged
  lines.concat(tail)
  full.concat(tail)
  why = if verdict == :refused then stop
        elsif verdict == :matched then nil
        else lines.grep(/^ {4}\s*\d+ [-+]/).first(2).map(&:strip).join(" | ")
        end
  row = Row.new(rel, verdict, lines, build_seconds, run_seconds, why)
  unless verdict == :matched
    %i[stdout stderr].each do |what|
      full << "  #{what} in full:"
      actual[what].each_line { |line| full << "    #{line.chomp}" }
    end
    keep_failure(row, full, bin, ran)
    lines << format("  %-10s %s", "report", row.report)
  end
  FileUtils.remove_entry(work) unless keep
  row
end

cases = select(filters)
jobs = [options[:jobs] || Etc.nprocessors, cases.size].min

# The runtime's object and the compiler's are caches every build reads;
# cold, every job would build them at once. One build of a program that
# evals makes both first, as `ze0 test` does.
if jobs > 1
  Dir.mktmpdir("ze0-warm-") do |work|
    program = File.join(work, "warm.rb")
    File.write(program, "eval('1')\n")
    system(RUNNER.build_env, *RUNNER.build_argv(program, File.join(work, "warm")), out: File::NULL, err: File::NULL)
  end
end
queue = Queue.new
cases.each_with_index { |rb, i| queue << [i, rb] }
done = Queue.new
workers = Array.new(jobs) do
  Thread.new do
    until queue.empty?
      i, rb = queue.pop(true) rescue break
      done << begin
        [i, one(rb, options)]
      rescue StandardError => e
        [i, Row.new(rb.delete_prefix("#{TESTS}/"), :backend, ["  #{e.class}: #{e.message}"], 0, 0, "#{e.class}: #{e.message}")]
      end
    end
  end
end

# One case prints in full as it finishes; a net prints a line each, and
# the whole of every program that did not match once they are all in.
rows = []
warn "#{cases.size} program(s), #{jobs} at a time" if cases.size > 1
cases.size.times do
  _, row = done.pop
  rows << row
  if cases.size == 1 || options[:verbose]
    puts "\ncase #{row.rel}"
    puts row.lines
  else
    puts format("%-9s %5.1fs build %5.1fs run  %s", row.verdict, row.build, row.run, row.rel)
  end
end
workers.each(&:join)
rows.sort_by!(&:rel)

if cases.size > 1 && !options[:verbose]
  rows.reject { |row| row.verdict == :matched }.each do |row|
    puts "\ncase #{row.rel}"
    puts row.lines
  end
  puts
  by = rows.group_by(&:verdict)
  %i[matched refused backend skipped diverged crashed timeout].each { |v| puts format("%-9s %d", v, (by[v] || []).size) }
  # The cases that did not match come last, so the end of the output
  # names them and where their reports are.
  rows.reject { |row| row.verdict == :matched || row.verdict == :skipped }.each do |row|
    puts format("  %-9s %s  %s", row.verdict, row.rel, row.report)
  end
end

path = File.join(ROOT, "tmp", "test-rows.txt")
FileUtils.mkdir_p(File.dirname(path))
File.open(path, "w") do |f|
  rows.reject { |row| row.verdict == :matched }.each do |row|
  f.puts "#{row.verdict} test/#{row.rel}\n    #{row.why}"
  f.puts "    report: #{row.report}" if row.report
end
end
puts "  every row: #{path}" if cases.size > 1
exit(rows.all? { |row| row.verdict == :matched } ? 0 : 1)
