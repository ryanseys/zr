# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/zr/runtime"
require_relative "../../lib/zr/native/build"
require_relative "../support/harness/answer"

# Ruby programs on the zr runtime. Each `test/programs/<name>.rb` runs
# under ruby (the reference), then compiled with the kernel, and under
# wasmtime. stdout, stderr and the exit status must be the same.
#
# A program under `test/programs/native/` reads the host (its
# environment, its working directory, its libSystem, or the stack that
# a fiber switches), so only the native target runs it. The directory
# identifies these programs, so no test reads a comment from a program.
#
# `ZR_GC_STRESS=1` adds a run that collects at every allocation.
#
# Compiling a program uses much memory at its peak. ruby grows its heap
# to the peak and does not give the pages back: over eight programs the
# live slots barely change (617,088 to 618,493), but the allocated heap
# pages go from 881 to 8,938, and `GC.compact` returns none of it. Thus
# each program runs in a fork pool worker, and a worker that has grown
# is closed and forked again.
class ProgramsTest < Minitest::Test
  # Longer than the default time limit of the pool for an example. A wasm
  # build is slow, not stuck: `sets` alone takes 44 s, mostly in the
  # backend's block ladder. The tier runs eight of these at once, each
  # forking six more processes, so one build can take more than three
  # minutes. With the default limit, the pool reported it as a hang.
  def self.deadline = 600

  # These allocate too much for a collection at every allocation.
  NO_STRESS = %w[heap_growth].freeze

  # Known defects of the wasm target, listed so that the run reports them.
  # Each is a program that is correct on the native target but not on
  # wasm. Each skips with a message that says what it does instead.
  #
  # `ZR_TEST_WASM_DEFECTS=0` runs them anyway. An entry here is a claim
  # about the wasm target today, and a claim can become false. The
  # variable checks the claims without an edit to this file. Remove an
  # entry that passes, and give its new output in the commit message.
  WASM_DEFECTS = {
    "core_batch" => "wasmtime holds 2325 MB to compile the 114 MB module and 2511 MB to run it, past the 2048 MB bound"
  }.freeze

  # `[stdout, stderr, status]` of `argv` under `env`. A run that goes past
  # a limit is killed, and its status gives the limit, so the test fails
  # and identifies the program.
  def capture(env, argv)
    answer = Checks.run(argv, env: env)
    why = Checks.killed(answer)
    [answer.stdout, answer.stderr, why ? "killed at #{why}" : answer.code]
  end

  def oracle(rb)
    capture({}, [RbConfig.ruby, rb])
  end

  def scrub(text, rb)
    Zr::Harness::Normalize.bytes(text, rb, File.dirname(rb))
  end

  def check(name, env, argv, want, rb)
    out, err, status = capture(env, argv)
    assert_equal want[2], status, "#{name} (#{env}) exited #{status}: #{out}#{err}"
    assert_equal scrub(want[0], rb), scrub(out, rb)
    assert_equal scrub(want[1], rb), scrub(err, rb)
  end

  EVERY_TARGET = Dir[File.join(ROOT, "test/programs/*.rb")].sort.freeze
  NATIVE_ONLY = Dir[File.join(ROOT, "test/programs/native/*.rb")].sort.freeze

  (EVERY_TARGET + NATIVE_ONLY).each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}") do
      want = oracle(rb)
      program = Zr.program(File.read(rb), rb)
      Dir.mktmpdir("zr-programs-") do |dir|
        bin = File.join(dir, name)
        assert_nil Zr::Native::Build.program(program, bin, work: dir)
        check(name, {}, [bin], want, rb)
        stress = ENV["ZR_GC_STRESS"] == "1" && !NO_STRESS.include?(name)
        check(name, { "ZR_GC_STRESS" => "1" }, [bin], want, rb) if stress
      end
    end

    next unless EVERY_TARGET.include?(rb)

    define_method("test_wasm_#{name}") do
      skip Checks.wasm_missing if Checks.wasm_missing
      skip WASM_DEFECTS[name] if WASM_DEFECTS.key?(name) && ENV["ZR_TEST_WASM_DEFECTS"] != "0"

      want = oracle(rb)
      program = Zr.program(File.read(rb), rb, target: Zr::Target::WASM32_WASI)
      Dir.mktmpdir("zr-programs-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Zr::Native::Build.wasm_program(program, wasm)
        # The program's directory at its own path, as ruby sees it.
        # error_highlight reads the source line from there.
        here = File.dirname(rb)
        check(name, {}, Zr::Harness::Wasmtime.run(wasm, dirs: { here => here }), want, rb)
      end
    end
  end
end
