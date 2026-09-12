# Runs one corpus program the way `ze0 test` runs it, and says as much
# about the run as a person fixing the program needs: what was built and
# how long it took, what the binary answered, and every line where that
# answer parts from ruby's recording.
#
#   ruby tools/test.rb core/io/a_stream_reads_what_it_holds.rb
#   ruby tools/test.rb core/range --keep --verbose
#
# A path names a case under test/, a directory of them, or any part of a
# case's name. The exit status is 0 when every case matched.
#
# `ze0 test` is the gate: it runs the corpus in parallel and writes one
# line per row. This tool is the bench beside it, for one program at a
# time.
require "fileutils"
require "rbconfig"
require "tmpdir"
require "timeout"
require_relative "../lib/ze0/harness/case"

ROOT = File.expand_path("..", __dir__)
TESTS = File.join(ROOT, "test")

options = { native: "ruby", gc: "plain", timeout: 60, keep: false, verbose: false, diff: 20 }
filters = []
argv = ARGV.dup
until argv.empty?
  word = argv.shift
  case word
  when "--native", "--gc" then options[word.delete_prefix("--").to_sym] = argv.shift
  when "--timeout", "--diff" then options[word.delete_prefix("--").to_sym] = Integer(argv.shift)
  when "--keep" then options[:keep] = true
  when "--verbose", "-v" then options[:verbose] = true
  when "-h", "--help" then abort File.read(__FILE__).lines.grep(/\A#/).join
  else filters << word
  end
end
abort "usage: ruby tools/test.rb <case path>... [--native ruby|cranelift] [--gc plain|stress] [--keep] [--verbose] [--diff N] [--timeout N]" if filters.empty?

# Every recorded program a filter names: a path, a directory, or any part
# of one, as `ze0 test` reads its filters.
def select(filters)
  every = Dir[File.join(TESTS, "*", "*.rb"), File.join(TESTS, "*", "*", "*.rb")].sort
  filters.flat_map do |filter|
    want = File.expand_path(filter.delete_prefix("./"), filter.start_with?("/") ? "/" : TESTS)
    found = every.select { |rb| rb == want || rb.start_with?("#{want}/") || rb.include?(filter.delete_prefix("test/")) }
    abort "no program matches #{filter.inspect}" if found.empty?

    found
  end.uniq
end

# A child with both streams captured, a wall-clock bound, and the time it
# took. The whole group goes on a timeout, so a child of the program
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
  answer = status.nil? ? Ze0::Harness::Answer.new(stdout, stderr, :timeout, nil) : Ze0::Harness::Answer.new(stdout, stderr, status.exitstatus || -1, status.termsig)
  [answer, seconds]
end

# Every line where the two answers part, numbered from 1, with the
# recording first. A stream that matches says so in one line.
def show_stream(what, want, got, limit)
  want_lines = want.lines
  got_lines = got.lines
  if want_lines == got_lines
    puts format("  %-10s %d line(s), the same", what, want_lines.size)
    return 0
  end

  puts format("  %-10s want %d line(s), got %d", what, want_lines.size, got_lines.size)
  shown = 0
  [want_lines.size, got_lines.size].max.times do |i|
    next if want_lines[i] == got_lines[i]
    if (shown += 1) > limit
      next
    end

    puts format("    %4d - %s", i + 1, want_lines[i] ? want_lines[i].chomp.inspect : "(no line)")
    puts format("    %4d + %s", i + 1, got_lines[i] ? got_lines[i].chomp.inspect : "(no line)")
  end
  puts "    ... #{shown - limit} more differing line(s) (--diff N)" if shown > limit
  shown
end

def report(kase, rb, expected, actual, options)
  puts format("  %-10s %s", "status", expected.status == actual.status ? "#{actual.status}, the same" : "want #{expected.status}, got #{actual.status}")
  differing = %i[stdout stderr].sum { |what| show_stream(what, expected[what], actual[what], options[:diff]) }
  if options[:verbose]
    %i[stdout stderr].each do |what|
      next if actual[what].empty?

      puts "  #{what} in full:"
      actual[what].each_line { |line| puts "    #{line}" }
    end
  end
  differing
end

rows = []
select(filters).each do |rb|
  rel = rb.delete_prefix("#{TESTS}/")
  kase = Ze0::Harness::Case.read(rb)
  puts
  puts "case #{rel}"
  directives = kase.directives
  puts format("  %-10s args=%s env=%s stdin=%s%s", "program", directives.args.inspect, directives.env.inspect, directives.stdin || "-",
              directives.only ? " only=#{directives.only}" : "")
  unless kase.recorded?
    puts "  #{"skipped".ljust(10)} no recording: run `ruby tools/record.rb #{rel}` first"
    rows << [rel, :skipped]
    next
  end

  work = Dir.mktmpdir("ze0-tool-test-")
  bin = File.join(work, "p")
  build = [RbConfig.ruby, File.join(ROOT, "bin/ze0"), "zr", "build", rel, "-o", bin, "--native", options[:native]]
  built, seconds = bounded(build, TESTS, nil, {}, options[:timeout])
  puts format("  %-10s %5.1fs %s", "build", seconds, built.code == 0 ? "ok" : "FAILED (#{built.status})")
  puts "  #{"command".ljust(10)} #{build.map { |w| w.include?(" ") ? w.inspect : w }.join(" ")}"
  if built.code != 0 || options[:verbose]
    [built.stdout, built.stderr].each { |text| text.each_line { |line| puts "    #{line}" } }
  end
  if built.code != 0
    rows << [rel, built.code == 3 ? :refused : :backend]
    FileUtils.remove_entry(work) unless options[:keep]
    puts "  #{"binary".ljust(10)} #{work} (kept)" if options[:keep]
    next
  end

  stdin = directives.stdin && File.binread(File.join(File.dirname(rb), directives.stdin))
  env = directives.env.merge(directives.zeo_env)
  env["ZR_GC_STRESS"] = "1" if options[:gc] == "stress"
  ran, seconds = bounded([bin, *directives.args], TESTS, stdin, env, options[:timeout])
  puts format("  %-10s %5.1fs %s", "run", seconds, ran.code == :timeout ? "ran past #{options[:timeout]}s" : ran.status)

  if ran.code == :timeout
    rows << [rel, :timeout]
  else
    expected = Ze0::Harness::Normalize.answer(kase.expected, rb, TESTS)
    actual = Ze0::Harness::Normalize.answer(ran, rb, TESTS)
    differing = report(kase, rb, expected, actual, options)
    stop = actual.stderr[/^(?:ze0: |.*?:in '[^']*': )?(.* is not implemented yet)(?: \((?:NotImplementedError|LoadError)\))?$/, 1]
    verdict = if expected == actual then :matched
              elsif stop then :refused
              elsif actual.signal && !expected.signal then :crashed
              else :diverged
              end
    puts format("  %-10s %s%s", "verdict", verdict, stop && verdict == :refused ? ": #{stop}" : "")
    puts format("  %-10s %d line(s) apart", "apart", differing) if verdict == :diverged
    rows << [rel, verdict]
  end
  puts "  #{"binary".ljust(10)} #{bin}" if options[:keep]
  FileUtils.remove_entry(work) unless options[:keep]
end

puts
rows.each { |rel, verdict| puts format("%-10s %s", verdict, rel) } if rows.size > 1
exit(rows.all? { |_, verdict| verdict == :matched } ? 0 : 1)
