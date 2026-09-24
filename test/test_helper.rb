# frozen_string_literal: true

require "minitest/autorun"

# The checks hold ruby's own road; a compiled compiler of the tree runs
# only where a check asks for it (lib/zr/compiled_compiler.rb).
ENV["ZR_SELF"] ||= "0"

require_relative "../lib/zr/target"
require_relative "support/fork_pool"
require_relative "support/harness/clean_env"
require "tmpdir"
require "fileutils"

# What earlier tiers left under the system's temporary directory when
# they were killed, or made in a worker that ended in `exit!`.
require_relative "support/scratch"
Zr::Test::Scratch.sweep

# Every example runs in a forked worker rather than in a thread: what
# these tests do is the compiler's own Ruby, and the GVL lets one
# thread at a time hold it. `MT_CPU` says how many workers.
#
# Every suite, and not a chosen few: a suite left serial runs in this
# process, and one compile here grows a heap ruby never gives back --
# which every later worker then inherits, because a fork starts from
# whatever this process has become. The parent stays a dispatcher.
Minitest.parallel_executor = Zr::Test::ForkPool.new
require_relative "support/slow"
require_relative "support/progress"
Minitest::Test.parallelize_me!

# Minitest's own report, and nothing over it. A progress bar stood here
# and was worse than the dots: it printed the time the whole run had
# been going beside each failure, so a check that answers in a tenth of
# a second read as `(57.20s)` for having failed late in a tier. `SLOW`
# asks for the times, and CI writes the JUnit file a failure renders
# from in the web view.
if ENV["SLOW"] || ENV["CI"]
  require "minitest/reporters"
  Minitest::Reporters.use!(
    [*(Minitest::Reporters::MeanTimeReporter.new(show_count: 25, show_all_runs: false) if ENV["SLOW"]),
     *(Minitest::Reporters::JUnitReporter.new(File.expand_path("../tmp/junit", __dir__)) if ENV["CI"])]
  )
end

ROOT = File.expand_path("..", __dir__)

require_relative "support/harness/wasmtime"
require_relative "support/built"

# What the checks share. A module and not the top level: a method
# defined there is a method on `Object`, which is exactly the collision
# `hygiene_test.rb` exists to refuse.
module Checks
  # A program a check runs must not be able to take the machine with it.
  # `test/programs/native/utf8.rb` on the wasm road allocates in a loop -- five
  # gigabytes in twelve seconds, and it never ends -- so a run is bounded
  # in time and in resident memory, and one that passes either bound is
  # killed and reads as a failure rather than as a hung machine.
  #
  # The memory is watched rather than asked for: wasmtime's own
  # `max-memory-size` bounds the module's linear memory and not what the
  # process resides in, which is what runs the machine out.
  LIMIT = Integer(ENV.fetch("ZR_LIMIT", 60))
  RESIDENT = Integer(ENV.fetch("ZR_RESIDENT", 2048))

  module_function

  def wasmtime? = Zr::Harness::Wasmtime.installed?

  # Why a check that builds a module for wasm32-wasi cannot run, or nil
  # with that target's caches loaded into this process. wasm is not
  # this host's road: `rake build:wasm` builds it on purpose, and a
  # check that finds it missing skips by name rather than builds.
  def wasm_missing
    return "wasmtime is not installed" unless wasmtime?
    return "wasm32-wasi is not built: run rake build:wasm" unless Zr::Test::Built.built?(Zr::Target::WASM32_WASI)

    Zr::Test::Built.load(Zr::Target::WASM32_WASI)
    nil
  end

  # `[stdout, why]` of `argv` under `env`, `why` naming the bound it
  # passed and nil when it stopped on its own. `$?` is the child's, as
  # `IO.popen` leaves it.
  #
  # The child runs outside this bundle; `Harness::CleanEnv` says why.
  def bounded(env, argv, err:, chdir: Dir.pwd)
    why = nil
    out = IO.popen(Zr::Harness::CleanEnv.env(env), argv, err: err, chdir: chdir,
                   unsetenv_others: true) do |io|
      watchdog = Thread.new { why = watch(io.pid) }
      io.read.tap { watchdog.kill }
    end
    [out, why]
  end

  # Watch `pid` until it stops or passes a bound, and kill it if it does.
  def watch(pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + LIMIT
    loop do
      passed = beyond(pid, deadline)
      return nil if passed == :done
      return passed.tap { Process.kill("KILL", pid) } if passed

      sleep 0.25
    end
  rescue StandardError
    nil
  end

  # Which bound `pid` has passed, nil while it is within both, and
  # `:done` once it has gone, which is what stops the watching.
  def beyond(pid, deadline)
    return "#{LIMIT}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

    rss = `ps -o rss= -p #{pid} 2>/dev/null`.to_i
    return :done if rss.zero?

    "#{RESIDENT} MB resident" if rss > RESIDENT * 1024
  end
end
