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
        stage = case argv
                in ["1"] then :one
                in ["2"] then :two
                else fail!("give the stage: 1 or 2")
                end
        alone { send(stage) }
      end

      ZR = Dev.path("exe/zr")
      LOCK = Dev.path("tmp/stage.lock")

      # Runs the block while this process holds the stage lock. A stage
      # takes 2-5 GB and every core it is given, so a second stage at the
      # same time swaps the machine; it stops at once instead. The system
      # drops the lock when this process ends, however it ends.
      def alone
        FileUtils.mkdir_p(File.dirname(LOCK))
        File.open(LOCK, File::RDWR | File::CREAT) do |lock|
          lock.flock(File::LOCK_EX | File::LOCK_NB) or
            fail!("another `zr-dev stage` runs now (#{LOCK} is locked); run one stage at a time")
          yield
        end
      end

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

      # zr under ruby compiles the compiler once. This checks that the
      # self-compile has no refusals. Stage 2 checks the bytes: the compiled
      # compiler must build the same binary as ruby, which a build that
      # depended on hash order or the time would not.
      def one
        Dev.tune!
        zr = stage1!
        puts "stage 1 passes: #{File.size(zr)} bytes of compiler, kept in #{zr}"
      end

      # Stage 1's binary, its cache and its stamp. They stay after a run, so
      # stage 2 and later work (`tmp/stage1/zr build app.rb`) reuse them.
      STAGE1 = Dev.path("tmp/stage1")
      STAGE1_ZR = File.join(STAGE1, "zr")
      STAMP = File.join(STAGE1, "zr.sources")
      # What a self-compile reads: the compiler, the runtime, the vendored
      # libraries and the locked gems.
      SOURCES = %w[exe lib vendor Gemfile.lock].freeze

      # Returns stage 1's binary: the kept one when it was built from these
      # sources, else a new build. The cache stays between builds; its keys
      # are the digests of what each entry was made from.
      def stage1!
        stamp = sources_stamp
        if stamp && File.executable?(STAGE1_ZR) && File.file?(STAMP) && File.read(STAMP) == stamp
          puts "stage 1: #{STAGE1_ZR} was built from these sources; it is used again"
          return STAGE1_ZR
        end

        FileUtils.rm_f([STAGE1_ZR, STAMP])
        FileUtils.mkdir_p(File.join(STAGE1, "cache"))
        env = BUILD_ENV.merge("ZR_CACHE" => File.join(STAGE1, "cache"))
        step("stage 1: ruby compiles the compiler -> #{STAGE1_ZR}") do
          system(env, Dev.ruby, ZR, "build", ZR, "-o", STAGE1_ZR, chdir: ROOT) or fail!("stage 1 did not build")
        end
        # A source that changed during the build makes a binary of neither
        # tree, so it gets no stamp and the next run builds again.
        File.write(STAMP, stamp) if stamp && stamp == sources_stamp
        STAGE1_ZR
      end

      # The git trees of SOURCES at HEAD, or nil when one of them has a
      # change that is not committed (or this is not a checkout): then no
      # stamp can name the sources.
      def sources_stamp
        status = Dev.git("status", "--porcelain", "--", *SOURCES) or return nil
        return nil unless status.empty?

        Dev.git("rev-parse", *SOURCES.map { |path| "HEAD:#{path}" })
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
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stages = [stage1!, Dev.path("tmp/stage2/zr")]
        puts "stage 1: #{File.size(stages[0])} bytes"

        # Stage 2 starts from an empty cache, so the compiled compiler makes
        # every entry itself.
        dir = File.dirname(stages[1])
        FileUtils.rm_rf(dir)
        FileUtils.mkdir_p(File.join(dir, "cache"))
        step("stage 2: stage 1 compiles the compiler -> #{stages[1]}") do
          system(BUILD_ENV.merge("ZR_CACHE" => File.join(dir, "cache")), stages[0], "build", ZR, "-o", stages[1]) or
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
