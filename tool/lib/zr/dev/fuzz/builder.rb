# frozen_string_literal: true

# The warm builder of `zr-dev fuzz`. It runs as a child of the fuzzer, on
# the copy of zr that `Suite.pin!` made, and loads only that copy's
# files: never the checkout's, which may change while a run goes on.
#
#   ruby builder.rb PIN [--coverage]
#
# It loads the compiler and the runtime once, and builds each program in
# a fork of itself, so a build costs its own compile and link, not a
# start of zr. Requests come on stdin and answers go on stdout, one JSON
# object to a line:
#
#   {"id": 7, "dir": "/abs/run", "file": "prog.rb", "out": "/abs/bin"}
#   {"id": 7, "status": 0, "signal": null, "stderr": "", "seconds": 0.41, "lines": [...]}
#
# `status` is the status of the build: 0 when the binary is written, 3
# for a refusal, 1 for a backend refusal and 70 for an internal error, as
# `zr build` gives them. `lines` are the compiler lines that the build ran
# and the warm-up did not, as "file:line", when `--coverage` is given.
#
# The first line it writes is {"ready": true, "env": {...}}: the
# environment that a binary runs with (`CLI::Runner.program_env`).
#
# This file must not require any file of the checkout. It is plain Ruby
# with no part of zr loaded at its top, so that Coverage can start before
# the compiler loads.

require "json"

pin = File.expand_path(ARGV.fetch(0))
coverage = ARGV.include?("--coverage")
jobs = Integer(ARGV.find { |a| a.start_with?("--jobs=") }&.delete_prefix("--jobs=") || 4)
limit = Integer(ARGV.find { |a| a.start_with?("--limit=") }&.delete_prefix("--limit=") || 180)
lib = File.join(pin, "lib")

# The collector limits and YJIT of a build (`CLI.tune!`): this starts the
# builder again with the limits, before Coverage and the compiler load.
require File.join(lib, "zr/config")
require File.join(lib, "zr/gc_tuning")
Zr::GcTuning.now(__FILE__, ARGV)

if coverage
  require "coverage"
  Coverage.setup(oneshot_lines: true)
  Coverage.resume
end

$LOAD_PATH.unshift(lib)
require File.join(lib, "zr/cli")
require File.join(lib, "zr/runtime")
require File.join(lib, "zr/native/build")

# The protocol goes to the stdout that the fuzzer reads. Anything else
# that writes to $stdout (a warning of the compiler) goes to stderr.
answers = $stdout.dup
answers.sync = true
$stdout.reopen($stderr)

runtime = Zr::Runtime.for
runtime.description
objects = [Zr::Native::Build.runtime_object(runtime, jobs: 1), Zr::Native::Build.eval_support_object(Zr::EvalSupport.for, jobs: 1)]
Zr::Native::Build.prelink([objects.first])
Zr::Native::Build.prelink(objects)

# The compiler directories whose lines count as coverage: the front end,
# the lowering and the backends, not the kernel's source (the runtime).
covered = %r{\A#{Regexp.escape(lib)}/zr/(?!runtime/)}
Coverage.result(stop: false, clear: true) if coverage

env = Zr::GcTuning.program_env.merge("ZR_RUBY" => Zr::CLI::Runner.pinned_launcher(Zr::CLI::Runner::EXE),
                                    "ZR_HOME" => Zr::CLI::Runner::HOME)
answers.puts(JSON.generate({ ready: true, env: env }))

# Builds one program in the fork. Writes the stderr of the build to
# `err`, and the coverage to `cov`.
build = lambda do |req, err, cov|
  $stderr.reopen(err, "w")
  $stdout.reopen($stderr)
  Dir.chdir(req.fetch("dir")) # rubocop:disable ThreadSafety/DirChdir -- the fork builds alone
  work = File.join(File.dirname(req.fetch("out")), "build")
  Dir.mkdir(work) unless Dir.exist?(work)
  status = 0
  begin
    program = Zr::CLI.command("build").lower(req.fetch("file"), Zr::BuildOptions.new, assemble: true)
    why = Zr::Native::Build.program(program, req.fetch("out"), work: work, jobs: 1)
    if why
      warn "zr: #{why}"
      status = 1
    end
  rescue SystemExit => e
    status = e.status
  rescue StandardError, ScriptError, SystemStackError, NoMemoryError => e
    warn "zr: internal error: #{e.class}: #{e.message}"
    (e.backtrace || []).first(40).each { |line| warn "\tfrom #{line.delete_prefix("#{lib}/")}" }
    status = Zr::CLI::Errors::DEFECT
  end
  if coverage
    lines = Coverage.result(stop: false, clear: false).flat_map do |file, data|
      next [] unless covered.match?(file)

      data[:oneshot_lines].map { |n| "#{file.delete_prefix("#{lib}/")}:#{n}" }
    end
    File.write(cov, JSON.generate(lines))
  end
  $stderr.flush
  exit!(status)
end

lock = Mutex.new
slots = Queue.new
jobs.times { slots << true }
threads = []
$stdin.each_line do |line|
  req = JSON.parse(line)
  slots.pop
  threads.select!(&:alive?)
  threads << Thread.new do
    err = "#{req.fetch("out")}.build.err"
    cov = "#{req.fetch("out")}.cov.json"
    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pid = fork { build.call(req, err, cov) }
    waiter = Thread.new { Process.wait2(pid).last }
    status = waiter.join(limit)&.value
    unless status
      begin
        Process.kill("KILL", pid)
      rescue Errno::ESRCH
        nil
      end
      waiter.join
    end
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began
    stderr = File.file?(err) ? File.binread(err) : +""
    lines = coverage && File.file?(cov) ? JSON.parse(File.read(cov)) : []
    answer = { id: req["id"], status: status&.exitstatus, signal: status&.termsig, timeout: status.nil?,
               stderr: stderr.force_encoding(Encoding::BINARY).scrub("?").encode("UTF-8", invalid: :replace, undef: :replace),
               seconds: seconds.round(3), lines: lines }
    lock.synchronize { answers.puts(JSON.generate(answer)) }
  ensure
    slots << true
  end
end
threads.each(&:join)
