# frozen_string_literal: true

# The tests run with `bin/minitest` (minitest's own runner), which
# `bin/zr-dev test` runs with its paths and options (tool/test.rb):
#
#   bin/zr-dev test                               every test: test/**/*_test.rb
#   bin/zr-dev test test/unit/cli_test.rb:40      the test on one line
#   bin/zr-dev test test/programs/core/gc try.rb  programs, from anywhere
#   bin/minitest test/unit/cli_test.rb -i /help/  bin/minitest itself, and its options
#
# The variables that a run reads, and the `zr-dev test` options that set
# most of them: docs/reference/environment-variables.md#for-the-tests.

# `COVERAGE=1` measures lib/. It starts before zr loads, because a file
# that loads earlier has no coverage.
require_relative "support/flag"
require_relative "support/coverage_run"
Zr::Test::CoverageRun.start(root: File.expand_path("..", __dir__)) if Zr::Test::CoverageRun.requested?

require "minitest/autorun"

require_relative "../lib/zr/target"
require_relative "../lib/zr/config"
# YJIT for the compiler that the workers run, and the collector limits of
# a compile for the processes they start (`GcTuning#now` with no script).
require_relative "../lib/zr/gc_tuning"
Zr::GcTuning.now
require_relative "support/fork_pool"
Zr::Test::CoverageRun.install(Zr::Test::ForkPool::Worker) if Zr::Test::CoverageRun.requested?
require_relative "support/harness/clean_env"
require "tmpdir"
require "fileutils"

# Remove the files that earlier tiers left in the system temporary
# directory. A tier that was killed, or a worker that ended in `exit!`,
# does not remove its own files.
require_relative "support/scratch"
Zr::Test::Scratch.sweep

# Every example runs in a forked worker, not in a thread. The tests run
# the compiler's Ruby code, and the GVL lets only one thread run it at a
# time. `MT_CPU` sets the number of workers.
#
# All suites run in workers. A serial suite runs in this process, and one
# compile grows a heap that ruby does not release. Each later fork gets
# a copy of that heap. So the parent process only dispatches work.
Minitest.parallel_executor = Zr::Test::ForkPool.new
require_relative "support/stubs"
Minitest::Test.include(Zr::Test::Stubs)
require_relative "support/history"
require_relative "support/progress"
Minitest::Test.parallelize_me!

ROOT = File.expand_path("..", __dir__)

require_relative "support/harness/wasmtime"
require_relative "support/harness/child"
require_relative "support/built"
Minitest.register_plugin(Zr::Test::Built)
require_relative "support/needs"
Zr::Test::Needs.install!
Minitest::Test.include(Zr::Test::Needs::Hook)
require_relative "support/pending"
Minitest::Test.include(Zr::Test::Pending::Hook)
# Read once here, so each forked worker has the list.
Zr::Test::Pending.reasons

# Helpers that the tests share. They are in a module, not at the top
# level. A top-level method becomes a method on `Object`, and
# `method_name_collision_test.rb` refuses that collision.
module Checks
  # The limits for a program that a test runs: Harness::Child::SECONDS,
  # and resident megabytes, Harness::Child::BUILD_MB unless the call
  # passes its own, as a test's child often builds. A program that goes
  # past a limit is killed, and the test fails. The wasmtime
  # `max-memory-size` option limits only the linear memory of the module,
  # so the harness watches the resident size.

  extend Zr::Test::Stubs

  module_function

  def wasmtime? = Zr::Harness::Wasmtime.installed?

  # Returns the reason that a test for wasm32-wasi cannot run. Returns nil
  # when it can run, and loads the caches of that target into this process.
  # The host build does not include wasm: `rake build:wasm` builds it.
  # A test that does not find it skips with the reason; it does not build.
  def wasm_missing
    return "wasmtime is not installed" unless wasmtime?
    return "wasm32-wasi is not built: run rake build:wasm" unless Zr::Test::Built.built?(Zr::Target::WASM32_WASI)

    Zr::Test::Built.load(Zr::Target::WASM32_WASI)
    nil
  end

  # Runs `argv` with `env` in its own process group, with the limits
  # above, and returns a `Harness::Answer`. Its code is the exit status,
  # or :timeout or :memory when the program goes past a limit. With
  # `merge`, stderr goes into stdout. The output is in the default
  # external encoding, as `IO.popen` gives it. The child runs outside
  # this bundle (`Harness::CleanEnv`).
  def run(argv, env: {}, chdir: Dir.pwd, merge: false, megabytes: Zr::Harness::Child::BUILD_MB)
    answer, = Zr::Harness::Child.run(argv, cwd: chdir, seconds: Zr::Harness::Child::SECONDS, megabytes: megabytes, env: env, merge: merge)
    answer.stdout.force_encoding(Encoding.default_external)
    answer.stderr.force_encoding(Encoding.default_external)
    answer
  end

  # Whether a snapshot test writes its file again (`ZR_BLESS=1`).
  def bless? = Zr::Test.flag?("ZR_BLESS")

  # Runs `zr-dev gen <name>` with `--check`, or with `ZR_BLESS=1`
  # writes the file again. Returns `[output, success]`.
  def generate(name, *argv)
    argv += ["--check"] unless bless?
    out = IO.popen([RbConfig.ruby, File.join(ROOT, "tool/zr-dev.rb"), "gen", name, *argv], err: %i[child out], &:read)
    [out, $?.success?]
  end

  # Runs the block as if this host were `triple` (`Zr::Target.host_triple`).
  def with_host(triple)
    stub_method(Zr::Target, :host_triple, triple) { yield }
  end

  # Returns the limit that stopped `answer`, or nil when it ended normally.
  def killed(answer)
    case answer.code
    when :timeout then "#{Zr::Harness::Child::SECONDS}s"
    when :memory then "its memory limit"
    end
  end
end
