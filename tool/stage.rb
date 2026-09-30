# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "lib/zr/dev"

module Zr
  module Dev
    # The self-compile stages. zr compiles `exe/zr`, the same compiler that
    # a user runs (no special version for these checks). These two checks
    # check that the compiler gives the same output as itself.
    #
    #   zr-dev stage 1   ruby compiles the compiler twice, to the same bytes
    #   zr-dev stage 2   the compiler compiled by itself is a fixed point
    class Stage < Command
      summary "Check that zr compiles itself to the same bytes (stage 1 or 2)"
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
        Dev.tune!
        # After a failure, the work directory stays, so you can compare the
        # two objects and their caches. After a pass, the task removes it.
        work = Dir.mktmpdir("zr-stage1-")
        puts "work (kept if this fails): #{work}"

        # The two self-compiles share nothing (each has its own cache and
        # output, and the tree is read-only). Thus they run at the same time,
        # with half the assembly workers each, if the machine has sufficient
        # memory. Each uses 1-2 GB under ruby, and its workers use the same
        # again. One after the other, they take 2 x 66 s.
        at_once = Native::Parallel.machine_bytes >= 12 * (1 << 30)
        jobs = at_once ? [Native::Build.jobs / 2, 1].max.to_s : nil
        started = %w[a b].map do |n|
          cache = File.join(work, "#{n}-cache")
          FileUtils.mkdir_p(cache)
          out = File.join(work, "#{n}.o")
          puts "self-compile #{n} -> #{out}#{" (at once, #{jobs} jobs each)" if at_once}"
          env = { "ZR_CACHE" => cache, "RUBYOPT" => nil, "RUBYLIB" => nil, "ZR_JOBS" => jobs }
          pid = spawn(env, Dev.ruby, ZR, "build", ZR, "-o", out, "--emit", "obj", chdir: ROOT)
          [n, at_once ? pid : Process.wait2(pid).last]
        end
        outs = started.map do |n, pid_or_status|
          status = pid_or_status.is_a?(Integer) ? Process.wait2(pid_or_status).last : pid_or_status
          fail!("self-compile #{n} failed; its work is in #{work}") unless status.success?
          digest = runtime_digest(File.join(work, "#{n}-cache"))
          runtime = File.join(work, "#{n}-cache", "store", "object", digest[0, 2], "#{digest}.o")
          fail!("the runtime object was not cached; the work is in #{work}") unless File.file?(runtime)

          [File.binread(File.join(work, "#{n}.o")), File.binread(runtime)]
        end

        a, b = outs
        %w[compiler runtime].each_with_index do |what, i|
          next if a[i] == b[i]

          at = a[i].bytes.zip(b[i].bytes).index { |x, y| x != y } || [a[i].bytesize, b[i].bytesize].min
          fail!("the two #{what} objects differ: #{a[i].bytesize} and #{b[i].bytesize} bytes, " \
                "first at #{at}; both are kept in #{work}")
        end
        puts "stage 1 passes: #{a[0].bytesize} bytes of compiler and #{a[1].bytesize} of runtime, the same twice"
        FileUtils.rm_rf(work)
        puts "nothing is kept: #{work} is gone"
      end

      # The runtime digest of the self-compile whose cache is `cache`: the
      # name of the one runtime symbol table there. The digest contains the
      # gem prelude's files, which only the self-compile's cache lists.
      def runtime_digest(cache)
        tables = Dir[File.join(cache, "store", "meta", "*", "*-symbols.json")]
        fail!("#{cache} has #{tables.size} runtime symbol tables, not one") unless tables.size == 1

        File.basename(tables.first, "-symbols.json")
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
        caches = stages.map { |path| { "ZR_CACHE" => File.join(File.dirname(path), "cache") } }

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
