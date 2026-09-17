# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/ze0/zr"
require_relative "../../lib/ze0/native/build"
require_relative "../support/harness/case"

# Ruby programs on the zr runtime: each `test/programs/<name>.rb` runs
# under ruby, the oracle, and then compiled with the kernel and under
# wasmtime; stdout, stderr and the exit status must agree.
#
# Which programs a road leaves out is written below as three lists of
# names rather than as a comment in each program that this file reads
# back: a list is data anyone can grep, and nothing has to parse prose.
#
# `ZE0_STRESS=1` adds the collect-at-every-allocation column.
#
# Compiling a program peaks high, and ruby grows its heap to the peak
# and does not give the pages back: over eight programs the live slots
# barely move (617,088 to 618,493) while the allocated heap pages go
# from 881 to 8,938, and `GC.compact` returns none of it. That is what
# the fork pool is for: each program runs in a worker, and a worker
# that has grown is closed and forked again.
class ProgramsTest < Minitest::Test
  # These read the host -- its environment, its working directory, its
  # libSystem or a stack a fiber switches -- so only the native road
  # runs them.
  NATIVE_ONLY = %w[
    bignums bindings caches callees core_gaps dates dispatch encodings_more
    enumerators environment eval_strings eval_under external fibers files
    files_and_copies files_more floats format_floats jit_loads jsons
    kernel_batch marshals monitors numeric_batch pathnames popens processes
    random_batch range_batch rationals requires self_compiles sockets stdlibs
    string_batch struct_batch threads times utf8 warnings_batch weak_tables
  ].freeze

  # These allocate too much for a collection at every allocation.
  NO_STRESS = %w[heap_growth].freeze

  # Defects of the wasm road, named so the run stays honest about them.
  # Each is a program whose native road is right and whose wasm road is
  # not, and each skips with what it does instead.
  WASM_DEFECTS = {
    "exceptions" => "an uncaught exception traps out of bounds instead of reporting and exiting 1"
  }.freeze

  # `[stdout, stderr, status]` of `argv` under `env`. A run that passes
  # a bound is killed, and its status says which bound rather than
  # nothing, so the check fails and names the program.
  def capture(env, argv)
    Dir.mktmpdir("ze0-programs-err-") do |dir|
      err = File.join(dir, "err")
      out, why = Checks.bounded(env, argv, err: err)
      [out, File.read(err), why ? "killed at #{why}" : $?.exitstatus]
    end
  end

  def oracle(rb)
    capture({}, [RbConfig.ruby, rb])
  end

  def scrub(text, rb)
    Ze0::Harness::Normalize.bytes(text, rb, File.dirname(rb))
  end

  def check(name, env, argv, want, rb)
    out, err, status = capture(env, argv)
    assert_equal want[2], status, "#{name} (#{env}) exited #{status}: #{out}#{err}"
    assert_equal scrub(want[0], rb), scrub(out, rb)
    assert_equal scrub(want[1], rb), scrub(err, rb)
  end

  Dir[File.join(ROOT, "test/programs/*.rb")].sort.each do |rb|
    name = File.basename(rb, ".rb")
    define_method("test_#{name}") do
      want = oracle(rb)
      program = Ze0::Zr.program(File.read(rb), rb)
      Dir.mktmpdir("ze0-programs-") do |dir|
        bin = File.join(dir, name)
        assert_nil Ze0::Native::Build.program(program, bin, work: dir)
        check(name, {}, [bin], want, rb)
        stress = ENV["ZE0_STRESS"] == "1" && !NO_STRESS.include?(name)
        check(name, { "ZR_GC_STRESS" => "1" }, [bin], want, rb) if stress
      end
    end

    define_method("test_wasm_#{name}") do
      skip "wasmtime is not installed" unless Checks.wasmtime?
      skip "the program reads the host" if NATIVE_ONLY.include?(name)
      skip WASM_DEFECTS[name] if WASM_DEFECTS.key?(name)

      want = oracle(rb)
      program = Ze0::Zr.program(File.read(rb), rb, target: Ze0::Target::WASM32_WASI)
      Dir.mktmpdir("ze0-programs-") do |dir|
        wasm = File.join(dir, "#{name}.wasm")
        assert_nil Ze0::Native::Build.wasm_program(program, wasm)
        # The program's directory at its own path, as ruby sees it:
        # error_highlight reads the source line it points at from there.
        here = File.dirname(rb)
        check(name, {}, [WASMTIME, "run", *WASM_FLAGS, "--dir", "#{here}::#{here}", wasm], want, rb)
      end
    end
  end
end
