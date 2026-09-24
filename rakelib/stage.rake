# frozen_string_literal: true

# The self-compile stages. zr compiles `exe/zr`, the same compiler that
# a user runs (no special version for these tasks). These two tasks
# check that the compiler gives the same output as itself.
#
#   rake stage1   # ruby compiles the compiler twice, to the same bytes
#   rake stage2   # the compiler compiled by itself is a fixed point

require "fileutils"
require "rbconfig"
require "tmpdir"
require_relative "../lib/zr/cli"
require_relative "../lib/zr/native/build"

module Stages
  ROOT = Zr::Paths::ROOT
  ZR = File.join(ROOT, "exe/zr")

  module_function

  # Prints `what`, runs the block, then prints the time it took, so that
  # a long step does not look like a hung one.
  def step(what)
    $stdout.sync = true
    print "#{what} ... "
    began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    puts format("%.1fs", Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)
    result
  end

  # zr under ruby compiles the compiler twice, in two processes, each with
  # its own cache. The bytes must be the same. This checks that the
  # self-compile is deterministic and has no refusals, without a compiled
  # binary. It compares the compiler object and the runtime object. The
  # stage 2 test needs a stage 1 binary that runs.
  def one
    zr_tune!
    # After a failure, the work directory stays, so you can compare the
    # two objects and their caches. After a pass, the task removes it.
    work = Dir.mktmpdir("zr-stage1-")
    puts "work (kept if this fails): #{work}"

    # The two self-compiles share nothing (each has its own cache and
    # output, and the tree is read-only). Thus they run at the same time,
    # with half the assembly workers each, if the machine has sufficient
    # memory. Each uses 1-2 GB under ruby, and its workers use the same
    # again. One after the other, they take 2 x 66 s.
    at_once = Zr::Native::Parallel.machine_bytes >= 12 * (1 << 30)
    jobs = at_once ? [Zr::Native::Build.jobs / 2, 1].max.to_s : nil
    started = %w[a b].map do |n|
      cache = File.join(work, "#{n}-cache")
      FileUtils.mkdir_p(cache)
      out = File.join(work, "#{n}.o")
      puts "self-compile #{n} -> #{out}#{" (at once, #{jobs} jobs each)" if at_once}"
      env = { "ZR_CACHE" => cache, "RUBYOPT" => nil, "RUBYLIB" => nil, "ZR_JOBS" => jobs }
      pid = spawn(env, RbConfig.ruby, ZR, "build", ZR, "-o", out, "--emit", "obj", chdir: ROOT)
      [n, at_once ? pid : Process.wait2(pid).last]
    end
    outs = started.map do |n, pid_or_status|
      status = pid_or_status.is_a?(Integer) ? Process.wait2(pid_or_status).last : pid_or_status
      abort("rake stage1: self-compile #{n} failed; its work is in #{work}") unless status.success?
      runtime = Dir[File.join(work, "#{n}-cache", "rt-*.o")]
      abort("rake stage1: the runtime object was not cached; the work is in #{work}") unless runtime.size == 1

      [File.binread(File.join(work, "#{n}.o")), File.binread(runtime.first)]
    end

    a, b = outs
    %w[compiler runtime].each_with_index do |what, i|
      next if a[i] == b[i]

      at = a[i].bytes.zip(b[i].bytes).index { |x, y| x != y } || [a[i].bytesize, b[i].bytesize].min
      abort("rake stage1: the two #{what} objects differ: #{a[i].bytesize} and #{b[i].bytesize} bytes, " \
            "first at #{at}; both are kept in #{work}")
    end
    puts "stage 1 holds: #{a[0].bytesize} bytes of compiler and #{a[1].bytesize} of runtime, the same twice"
    FileUtils.rm_rf(work)
    puts "nothing is kept: #{work} is gone"
  end

  # Stage 1 is the compiler compiled by zr under ruby. Stage 2 is the same
  # source compiled by stage 1, called as a user calls `zr`. The two
  # binaries must be the same, byte for byte: this shows that the
  # compiler is a fixed point. Both have the same base name, because the
  # macOS ad-hoc signature includes the output's base name.
  #
  # Stage 1 uses the number of workers that memory permits
  # (`Parallel.afforded`), unless `ZR_JOBS` sets it. A worker of the
  # compiled compiler contains the compiler's full heap (7.6 GB on a
  # 16 GB machine), so six workers cause swapping.
  #
  # zr's own linker links both binaries (stage 2's inside the compiled
  # compiler), so this also checks that the linker is a fixed point. The
  # UUID is the image's hash, and the signature hashes the image, so both
  # follow from the other bytes. The comparison still ignores them: with
  # `ZR_LINKER=cc`, `ld` writes a new UUID and signature for each link.
  def two
    zr_tune!
    stages = (1..2).map do |n|
      dir = File.join(ROOT, "tmp/stage#{n}")
      FileUtils.rm_rf(dir)
      FileUtils.mkdir_p(File.join(dir, "cache"))
      File.join(dir, "zr")
    end
    caches = stages.map { |path| { "ZR_CACHE" => File.join(File.dirname(path), "cache") } }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    step("stage 1: ruby compiles the compiler -> #{stages[0]}") do
      system(caches[0], RbConfig.ruby, ZR, "build", ZR, "-o", stages[0]) or
        abort("rake stage2: stage 1 did not build")
    end
    puts "stage 1: #{File.size(stages[0])} bytes"
    step("stage 2: stage 1 compiles the compiler -> #{stages[1]}") do
      system(caches[1], stages[0], "build", ZR, "-o", stages[1]) or
        abort("rake stage2: stage 1 did not compile the compiler")
    end

    a, b = stages.map { |path| File.binread(path) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    linker = Zr::Native::Build.linker(Zr::Target.default)
    stamps = linker.stamps(a)
    x, y = [a, b].map do |bytes|
      bytes.dup.tap { |out| linker.stamps(bytes).each { |r| out[r] = "\0".b * r.size } }
    end

    if x == y
      puts format("stage 2 holds: %d bytes, the same from stage 1 and from ruby, in %.1f s", a.bytesize, elapsed)
      unless stamps.empty?
        puts "the linker's own stamps are not compared: #{stamps.map { |r| "#{r.first}..#{r.last}" }.join(", ")}"
      end
      puts "both binaries are kept: #{stages.join(" and ")}"
    else
      at = x.bytesize.times.find { |i| x.getbyte(i) != y.getbyte(i) } || [x.bytesize, y.bytesize].min
      abort("rake stage2: #{a.bytesize} and #{b.bytesize} bytes, first differing at #{at}")
    end
  end
end

desc "zr compiles itself twice, to the same bytes"
task(:stage1) { Stages.one }

desc "The compiler compiled by itself is a fixed point"
task(:stage2) { Stages.two }
