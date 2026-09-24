# frozen_string_literal: true

require "minitest/autorun"

# The checks hold ruby's own road; a compiled compiler of the tree runs
# only where a check asks for it (lib/zr/compiled_compiler.rb).
ENV["ZR_COMPILED"] ||= "0"

require_relative "../lib/zr/target"
require_relative "../lib/zr/flags"
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
require_relative "support/stubs"
Minitest::Test.include(Zr::Test::Stubs)
require_relative "support/slow"
require_relative "support/progress"
Minitest::Test.parallelize_me!

# Minitest's own report, and nothing over it. A progress bar stood here
# and was worse than the dots: it printed the time the whole run had
# been going beside each failure, so a check that answers in a tenth of
# a second read as `(57.20s)` for having failed late in a tier. `SLOW`
# asks for the times, and CI writes the JUnit file a failure renders
# from in the web view.
if Zr.flag?("SLOW") || ENV["CI"]
  require "minitest/reporters"
  Minitest::Reporters.use!(
    [*(Minitest::Reporters::MeanTimeReporter.new(show_count: 25, show_all_runs: false) if Zr.flag?("SLOW")),
     *(Minitest::Reporters::JUnitReporter.new(File.expand_path("../tmp/junit", __dir__)) if ENV["CI"])]
  )
end

ROOT = File.expand_path("..", __dir__)

require_relative "support/harness/wasmtime"
require_relative "support/harness/child"
require_relative "support/built"

# What the checks share. A module and not the top level: a method
# defined there is a method on `Object`, which is exactly the collision
# `hygiene_test.rb` exists to refuse.
module Checks
  # The bounds on a program that a test runs, in seconds and in resident
  # megabytes. A program that passes one is killed, and the test fails.
  # wasmtime's own `max-memory-size` bounds only the module's linear
  # memory, so the process's resident size is watched instead.
  LIMIT = Integer(ENV.fetch("ZR_TEST_SECONDS", 60))
  RESIDENT = Integer(ENV.fetch("ZR_TEST_RESIDENT_MB", 2048))

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

  # The answer (`Harness::Answer`) of `argv` under `env`, run in its
  # own process group under the bounds above. Its code is the exit
  # status, or :timeout or :memory for a bound it passed. With `merge`,
  # stderr goes into stdout. The output is in the default external
  # encoding, as `IO.popen` gives it. The child runs outside this bundle
  # (`Harness::CleanEnv`).
  def run(argv, env: {}, chdir: Dir.pwd, merge: false)
    answer, = Zr::Harness::Child.run(argv, cwd: chdir, seconds: LIMIT, megabytes: RESIDENT, env: env, merge: merge)
    answer.stdout.force_encoding(Encoding.default_external)
    answer.stderr.force_encoding(Encoding.default_external)
    answer
  end

  # Why `answer` did not finish on its own, or nil when it did.
  def killed(answer)
    case answer.code
    when :timeout then "#{LIMIT}s"
    when :memory then "#{RESIDENT} MB resident"
    end
  end
end
