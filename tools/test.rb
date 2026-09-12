# Runs corpus programs the way `ze0 test` runs them, and says as much
# about each run as a person fixing the program needs: what was built
# and how long it took, what the binary answered, and every line where
# that answer parts from ruby's recording.
#
#   ruby tools/test.rb core/io/a_stream_reads_what_it_holds.rb
#   ruby tools/test.rb core/io core/file            # a net, in parallel
#   ruby tools/test.rb core/range --keep --verbose
#
# A path names a case under test/, a directory of them, or any part of a
# case's name. One case prints in full; a net prints a line for each and
# the whole of every program that did not match. The exit status is 0
# when every case matched.
#
# Every row but the matched ones is written to tmp/test-rows.txt, in the
# shape `ze0 test` writes tmp/sweep.txt, so the two compare.
require "etc"
require "fileutils"
require "rbconfig"
require "tmpdir"
require "timeout"
require_relative "../lib/ze0/harness/case"

ROOT = File.expand_path("..", __dir__)
TESTS = File.join(ROOT, "test")

options = { gc: "plain", timeout: 60, keep: false, verbose: false, diff: 20, jobs: nil }
filters = []
argv = ARGV.dup
until argv.empty?
  word = argv.shift
  case word
  when "--gc" then options[word.delete_prefix("--").to_sym] = argv.shift
  when "--timeout", "--diff", "--jobs" then options[word.delete_prefix("--").to_sym] = Integer(argv.shift)
  when "-j" then options[:jobs] = Integer(argv.shift)
  when "--keep" then options[:keep] = true
  when "--verbose", "-v" then options[:verbose] = true
  when "-h", "--help" then abort File.read(__FILE__).lines.grep(/\A#/).join
  else filters << word
  end
end
abort "usage: ruby tools/test.rb <case path>... [--jobs N] [--gc plain|stress] [--keep] [--verbose] [--diff N] [--timeout N]" if filters.empty?

Row = Struct.new(:rel, :verdict, :lines, :build, :run, :why)

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

# A child with both streams captured, a wall-clock bound, and the time
# it took. The whole group goes on a timeout, so a child of the program
# cannot hold the pipes open.
def bounded(argv, cwd, stdin, env, limit)
  env = { "RUBYOPT" => nil, "RUBYLIB" => nil }.merge(env)
  out_r, out_w = IO.pipe
  err_r, err_w = IO.pipe
  in_r, in_w = IO.pipe
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pid = Process.spawn(env, *argv, chdir: cwd, in: in_r, out: out_w, err: err_w, pgroup: true)
  [out_w, err_w, in_r].each(&:close)
  writer = Thread.new do
    in_w.binmode
    in_w.write(stdin) if stdin
  rescue Errno::EPIPE
    nil
  ensure
    in_w.close
  end
  reader = [out_r, err_r].map { |io| Thread.new { io.binmode; io.read } }
  status = nil
  begin
    Timeout.timeout(limit) { _, status = Process.wait2(pid) }
  rescue Timeout::Error
    Process.kill("KILL", -pid) rescue nil
    Process.wait(pid) rescue nil
  end
  writer.join
  stdout, stderr = reader.map(&:value)
  seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  answer = if status.nil?
             Ze0::Harness::Answer.new(stdout, stderr, :timeout, nil)
           else
             Ze0::Harness::Answer.new(stdout, stderr, status.exitstatus || -1, status.termsig)
           end
  [answer, seconds]
end

# Every line where the two answers part, numbered from 1, the recording
# first. A stream that matches says so in one line.
def stream_lines(what, want, got, limit)
  want_lines = want.lines
  got_lines = got.lines
  return [format("  %-10s %d line(s), the same", what, want_lines.size), 0] if want_lines == got_lines

  out = [format("  %-10s want %d line(s), got %d", what, want_lines.size, got_lines.size)]
  apart = 0
  [want_lines.size, got_lines.size].max.times do |i|
    next if want_lines[i] == got_lines[i]

    apart += 1
    next if apart > limit

    out << format("    %4d - %s", i + 1, want_lines[i] ? want_lines[i].chomp.inspect : "(no line)")
    out << format("    %4d + %s", i + 1, got_lines[i] ? got_lines[i].chomp.inspect : "(no line)")
  end
  out << "    ... #{apart - limit} more differing line(s) (--diff N)" if apart > limit
  [out, apart]
end

# One program: built, run, and compared. Its whole report comes back as
# lines, so that programs running side by side do not interleave.
def one(rb, options)
  rel = rb.delete_prefix("#{TESTS}/")
  kase = Ze0::Harness::Case.read(rb)
  directives = kase.directives
  lines = [format("  %-10s args=%s env=%s stdin=%s%s", "program", directives.args.inspect, directives.env.inspect,
                  directives.stdin || "-", directives.only ? " only=#{directives.only}" : "")]
  unless kase.recorded?
    lines << "  #{"skipped".ljust(10)} no recording: run `ruby tools/record.rb #{rel}` first"
    return Row.new(rel, :skipped, lines, 0, 0, "no recording")
  end

  work = Dir.mktmpdir("ze0-tool-test-")
  keep = options[:keep]
  bin = File.join(work, "p")
  build = [RbConfig.ruby, File.join(ROOT, "bin/ze0"), "zr", "build", rel, "-o", bin]
  built, build_seconds = bounded(build, TESTS, nil, {}, options[:timeout])
  lines << format("  %-10s %5.1fs %s", "build", build_seconds, built.code == 0 ? "ok" : "FAILED (#{built.status})")
  lines << "  #{"command".ljust(10)} #{build.join(" ")}"
  if built.code != 0 || options[:verbose]
    [built.stdout, built.stderr].each { |text| text.each_line { |line| lines << "    #{line.chomp}" } }
  end
  if built.code != 0
    lines << "  #{"binary".ljust(10)} #{work} (kept)" if keep
    FileUtils.remove_entry(work) unless keep
    why = (built.stderr.empty? ? built.stdout : built.stderr).lines.first.to_s.strip
    return Row.new(rel, built.code == 3 ? :refused : :backend, lines, build_seconds, 0, why)
  end

  stdin = directives.stdin && File.binread(File.join(File.dirname(rb), directives.stdin))
  env = directives.env.merge(directives.zeo_env)
  env["ZR_GC_STRESS"] = "1" if options[:gc] == "stress"
  ran, run_seconds = bounded([bin, *directives.args], TESTS, stdin, env, options[:timeout])
  lines << format("  %-10s %5.1fs %s", "run", run_seconds, ran.code == :timeout ? "ran past #{options[:timeout]}s" : ran.status)
  lines << "  #{"binary".ljust(10)} #{bin}" if keep
  FileUtils.remove_entry(work) unless keep
  if ran.code == :timeout
    return Row.new(rel, :timeout, lines, build_seconds, run_seconds, "ran past #{options[:timeout]}s")
  end

  expected = Ze0::Harness::Normalize.answer(kase.expected, rb, TESTS)
  actual = Ze0::Harness::Normalize.answer(ran, rb, TESTS)
  lines << format("  %-10s %s", "status",
                  expected.status == actual.status ? "#{actual.status}, the same" : "want #{expected.status}, got #{actual.status}")
  apart = 0
  %i[stdout stderr].each do |what|
    said, n = stream_lines(what, expected[what], actual[what], options[:diff])
    lines.concat(Array(said))
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
            elsif actual.signal && !expected.signal then :crashed
            else :diverged
            end
  lines << format("  %-10s %s%s", "verdict", verdict, stop && verdict == :refused ? ": #{stop}" : "")
  lines << format("  %-10s %d line(s) apart", "apart", apart) if verdict == :diverged
  why = if verdict == :refused then stop
        elsif verdict == :matched then nil
        else lines.grep(/^ {4}\s*\d+ [-+]/).first(2).map(&:strip).join(" | ")
        end
  Row.new(rel, verdict, lines, build_seconds, run_seconds, why)
end

cases = select(filters)
jobs = [options[:jobs] || Etc.nprocessors, cases.size].min
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
end

path = File.join(ROOT, "tmp", "test-rows.txt")
FileUtils.mkdir_p(File.dirname(path))
File.open(path, "w") do |f|
  rows.reject { |row| row.verdict == :matched }.each { |row| f.puts "#{row.verdict} test/#{row.rel}\n    #{row.why}" }
end
puts "  every row: #{path}" if cases.size > 1
exit(rows.all? { |row| row.verdict == :matched } ? 0 : 1)
