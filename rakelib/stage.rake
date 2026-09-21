# frozen_string_literal: true

# The stage ladder. `exe/ze0` -- the compiler a user runs, and nothing
# written for the ladder alone -- is the program ze0 compiles; these two
# tasks are what hold it to itself.
#
#   rake stage1   # ruby compiles the compiler twice, to the same bytes
#   rake stage2   # the compiler compiled by itself is a fixed point

require "fileutils"
require "rbconfig"
require "tmpdir"
require_relative "../lib/ze0/cli"
require_relative "../lib/ze0/native/build"

module Stages
  ROOT = Ze0::Paths::ROOT
  ZE0 = File.join(ROOT, "exe/ze0")

  module_function

  # ze0 under ruby compiles the compiler twice, in two processes with a
  # cache of its own each, and the bytes must agree: the self-compile
  # stays deterministic and refusal-free with no binary in the loop.
  # Both objects are compared, the compiler's and the runtime's. The
  # stage-2 fixed point needs a stage-1 binary that runs.
  def one
    ze0_tune!
    # The work directory outlives a failure, so the two objects and
    # their caches are there to diff; a run that holds removes it, as
    # the two objects are then the same bytes twice.
    work = Dir.mktmpdir("ze0-stage1-")
    puts "work (kept if this fails): #{work}"

    outs = %w[a b].map do |n|
      cache = File.join(work, "#{n}-cache")
      FileUtils.mkdir_p(cache)
      out = File.join(work, "#{n}.o")
      Ze0::CLI.step("self-compile #{n} -> #{out}") do
        system({ "ZE0_CACHE" => cache, "RUBYOPT" => nil, "RUBYLIB" => nil },
               RbConfig.ruby, ZE0, "build", ZE0, "-o", out, "--emit", "obj", chdir: ROOT) or
          abort("rake stage1: the self-compile failed; its work is in #{work}")
      end
      runtime = Dir[File.join(cache, "rt-*.o")]
      abort("rake stage1: the runtime object was not cached; the work is in #{work}") unless runtime.size == 1

      [File.binread(out), File.binread(runtime.first)]
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

  # Stage 1 is the compiler compiled by ze0 under ruby; stage 2 is the
  # same source compiled by stage 1, called as a user calls `ze0`. The
  # two binaries must agree byte for byte, which is what says the
  # compiler is a fixed point. Both are written under the same base
  # name, since macOS's ad-hoc signature carries the output's base name.
  #
  # Stage 1 builds in one process unless `ZE0_JOBS` says otherwise: a
  # worker of the compiled compiler holds the compiler's whole heap, and
  # six of them have driven this sixteen-gigabyte machine into swap
  # (task #24).
  #
  # ze0's own linker links both, stage 2's inside the compiled compiler,
  # so the comparison holds the linker to the same fixed point. Its UUID
  # is the image's hash, and the signature hashes the image, so both
  # follow from the rest. They are blanked all the same: under
  # `ZE0_LINK=cc`, `ld` writes a fresh UUID each link and the signature
  # over its page, and no input decides those.
  def two
    ze0_tune!
    stages = (1..2).map do |n|
      dir = File.join(ROOT, "tmp/stage#{n}")
      FileUtils.rm_rf(dir)
      FileUtils.mkdir_p(File.join(dir, "cache"))
      File.join(dir, "ze0")
    end
    caches = stages.map { |path| { "ZE0_CACHE" => File.join(File.dirname(path), "cache") } }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Ze0::CLI.step("stage 1: ruby compiles the compiler -> #{stages[0]}") do
      system(caches[0], RbConfig.ruby, ZE0, "build", ZE0, "-o", stages[0]) or
        abort("rake stage2: stage 1 did not build")
    end
    puts "stage 1: #{File.size(stages[0])} bytes"
    Ze0::CLI.step("stage 2: stage 1 compiles the compiler -> #{stages[1]}") do
      system({ "ZE0_JOBS" => ENV.fetch("ZE0_JOBS", "1") }.merge(caches[1]), stages[0], "build", ZE0, "-o", stages[1]) or
        abort("rake stage2: stage 1 did not compile the compiler")
    end

    a, b = stages.map { |path| File.binread(path) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    linker = Ze0::Native::Build.linker(Ze0::Target.default)
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

desc "ze0 compiles itself twice, to the same bytes"
task(:stage1) { Stages.one }

desc "The compiler compiled by itself is a fixed point"
task(:stage2) { Stages.two }
