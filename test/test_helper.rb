# frozen_string_literal: true

require "minitest/autorun"

# The tests run the compiler on the host ruby. A test that needs the
# compiled compiler turns it on itself (lib/zr/bootstrap/handoff.rb).
ENV["ZR_COMPILED"] ||= "0"

require_relative "../lib/zr/target"
require_relative "../lib/zr/flags"
require_relative "support/fork_pool"
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
require_relative "support/slow"
require_relative "support/progress"
Minitest::Test.parallelize_me!

# Use the Minitest report by default. `SLOW` adds the time of each test.
# On CI, write a JUnit file, which the web view uses to show failures.
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

# Helpers that the tests share. They are in a module, not at the top
# level. A top-level method becomes a method on `Object`, and
# `method_name_collision_test.rb` refuses that collision.
module Checks
  # The limits for a program that a test runs, in seconds and in resident
  # megabytes. A program that goes past a limit is killed, and the test
  # fails. The wasmtime `max-memory-size` option limits only the linear
  # memory of the module, so the harness watches the resident size.
  LIMIT = Integer(ENV.fetch("ZR_TEST_SECONDS", 60))
  RESIDENT = Integer(ENV.fetch("ZR_TEST_RESIDENT_MB", 2048))

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
  def run(argv, env: {}, chdir: Dir.pwd, merge: false)
    answer, = Zr::Harness::Child.run(argv, cwd: chdir, seconds: LIMIT, megabytes: RESIDENT, env: env, merge: merge)
    answer.stdout.force_encoding(Encoding.default_external)
    answer.stderr.force_encoding(Encoding.default_external)
    answer
  end

  # Runs `zr-dev gen <name>` with `--check`, or with `ZR_BLESS=1`
  # writes the file again. Returns `[output, success]`.
  def generate(name, *argv)
    argv += ["--check"] unless ENV["ZR_BLESS"] == "1"
    out = IO.popen([RbConfig.ruby, File.join(ROOT, "tool/zr-dev.rb"), "gen", name, *argv], err: %i[child out], &:read)
    [out, $?.success?]
  end

  # Runs the block as if this host were `triple` (`Zr::Target.host_triple`).
  def with_host(triple)
    target = Zr::Target.singleton_class
    target.alias_method(:real_host_triple, :host_triple)
    target.define_method(:host_triple) { triple }
    yield
  ensure
    target.alias_method(:host_triple, :real_host_triple)
    target.remove_method(:real_host_triple)
  end

  # Returns the limit that stopped `answer`, or nil when it ended normally.
  def killed(answer)
    case answer.code
    when :timeout then "#{LIMIT}s"
    when :memory then "#{RESIDENT} MB resident"
    end
  end
end
