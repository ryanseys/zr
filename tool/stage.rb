# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "lib/zr/dev"

module Zr
  module Dev
    # The self-compile stages. zr compiles `exe/zr`, the same compiler that
    # a user runs (no special version for these checks). These two checks
    # check that the compiler compiles itself, and gives the same output
    # as itself.
    #
    #   zr-dev stage 1   ruby compiles the compiler, with no refusals
    #   zr-dev stage 2   the compiler compiled by itself is a fixed point
    class Stage < Command
      summary "Check that zr compiles itself (stage 1), to the same bytes (stage 2)"
      usage "1|2"

      def run(argv)
        require_relative "../lib/zr/cli"
        require_relative "../lib/zr/native/build"
        case argv
        in ["1"] then one
        in ["2"] then two
        else fail!("give the stage: 1 or 2")
        end
      end

      ZR = Dev.path("exe/zr")

      # Each build prints a line to stderr as each of its phases ends
      # (`Zr::Timing`), so a long self-compile shows where it is.
      BUILD_ENV = { "ZR_TIMING" => "1", "RUBYOPT" => nil, "RUBYLIB" => nil }.freeze

      # Prints `what`, runs the block, then prints the time it took. The
      # build's phase lines come between the two.
      def step(what)
        $stdout.sync = true
        puts "#{what} ..."
        began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        puts format("#{what}: %.1fs", Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)
        result
      end

      # zr under ruby compiles the compiler once, to an object, with its own
      # cache. This checks that the self-compile has no refusals, without
      # a compiled binary. Stage 2 checks the bytes: the compiled compiler
      # must build the same binary as ruby, which a build that depended on
      # hash order or the time would not.
      def one
        Dev.tune!
        # After a failure, the work directory stays, so you can look at the
        # object and the cache. After a pass, the task removes it.
        work = Dir.mktmpdir("zr-stage1-")
        puts "work (kept if this fails): #{work}"
        cache = File.join(work, "cache")
        FileUtils.mkdir_p(cache)
        out = File.join(work, "zr.o")
        env = BUILD_ENV.merge("ZR_CACHE" => cache)
        step("self-compile -> #{out}") do
          system(env, Dev.ruby, ZR, "build", ZR, "-o", out, "--emit", "obj", chdir: ROOT) or
            fail!("the self-compile failed; its work is in #{work}")
        end
        puts "stage 1 passes: #{File.size(out)} bytes of compiler"
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
        Dev.tune!
        stages = (1..2).map do |n|
          dir = File.join(ROOT, "tmp/stage#{n}")
          FileUtils.rm_rf(dir)
          FileUtils.mkdir_p(File.join(dir, "cache"))
          File.join(dir, "zr")
        end
        caches = stages.map { |path| BUILD_ENV.merge("ZR_CACHE" => File.join(File.dirname(path), "cache")) }

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        step("stage 1: ruby compiles the compiler -> #{stages[0]}") do
          system(caches[0], Dev.ruby, ZR, "build", ZR, "-o", stages[0]) or
            fail!("stage 1 did not build")
        end
        puts "stage 1: #{File.size(stages[0])} bytes"
        step("stage 2: stage 1 compiles the compiler -> #{stages[1]}") do
          system(caches[1], stages[0], "build", ZR, "-o", stages[1]) or
            fail!("stage 1 did not compile the compiler")
        end

        a, b = stages.map { |path| File.binread(path) }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        linker = Native::Build.linker(Target.default)
        stamps = linker.stamps(a)
        x, y = [a, b].map do |bytes|
          bytes.dup.tap { |out| linker.stamps(bytes).each { |r| out[r] = "\0".b * r.size } }
        end

        if x == y
          puts format("stage 2 passes: %d bytes, the same from stage 1 and from ruby, in %.1f s", a.bytesize, elapsed)
          unless stamps.empty?
            puts "the linker's own stamps are not compared: #{stamps.map { |r| "#{r.first}..#{r.last}" }.join(", ")}"
          end
          puts "both binaries are kept: #{stages.join(" and ")}"
        else
          at = x.bytesize.times.find { |i| x.getbyte(i) != y.getbyte(i) } || [x.bytesize, y.bytesize].min
          fail!("#{a.bytesize} and #{b.bytesize} bytes, first differing at #{at}")
        end
      end
    end
  end
end
