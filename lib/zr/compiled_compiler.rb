# frozen_string_literal: true

require "rbconfig"
require_relative "paths"

module Zr
  # The compiler zr compiled, run in place of the one ruby runs: the
  # same code, the same answers (`rake stage2` holds it to that), and a
  # warm build takes less time under it.
  #
  # `exe/zr` asks here first. The compiled compiler answers a build only
  # while every file it was built from is as it was then: the stamp of
  # each file under lib/, runtime/, vendor/, the library tree and of exe/zr,
  # and the same list of files. Anything else is a miss, and ruby runs
  # the command. An installed gem builds the compiled compiler at its
  # first build and says so; a checkout, whose files change all day,
  # builds one only under `ZR_COMPILED=1` or `rake build:self`.
  # `ZR_COMPILED=0` never hands the command over.
  module CompiledCompiler
    # The commands a compiled compiler takes over. The others answer at
    # once under ruby.
    VERBS = %w[run build machine].freeze

    module_function

    def dir = File.join(Paths.cache, "self")
    def binary = File.join(dir, "zr")
    def manifest = File.join(dir, "manifest.marshal")

    # The command goes to the compiled compiler when it is current, or
    # once one is built for a first build that may build it. Under the
    # compiled compiler itself, and for any other command, nothing
    # happens here.
    def hand_over(argv, env = ENV)
      return if Zr.compiled? || !VERBS.include?(argv.first)
      return if env["ZR_COMPILED"] == "0"

      build if !current? && (env["ZR_COMPILED"] == "1" || !Paths.checkout?)
      # The compiled compiler has no rubygems, so a pin it must resolve
      # again is resolved by this ruby.
      exec({ "ZR_HOST_RUBY" => RbConfig.ruby }, binary, *argv) if current?
    end

    # Every file a compiled compiler is built from, and its stamp.
    # The library tree counts too: a pin that moves names another tree.
    def sources
      [File.join(Paths::ROOT, "exe/zr"), *Dir[File.join(Paths::ROOT, "{lib,runtime,vendor}/**/*")], *library_files].select { |f| File.file?(f) }.sort
    end

    # The files of the library tree, found by ruby's rubygems where the
    # manifest is stale. A tree that does not resolve names nothing, and
    # ruby then runs the build and says why.
    def library_files
      require_relative "libraries"
      Dir[File.join(Libraries.tree, "**/*")]
    rescue Libraries::Unresolved
      [File.join(Libraries.dir, "unresolved")]
    end

    def stamps(files = sources)
      files.to_h do |f|
        s = File.stat(f)
        [f, [s.size, s.mtime.to_r, s.ctime.to_r, s.ino]]
      end
    end

    def current?
      return false unless File.file?(binary) && File.executable?(binary) && File.file?(manifest)

      Marshal.load(File.binread(manifest)) == stamps
    rescue StandardError
      false
    end

    # The compiled compiler, built by ruby from this tree, and the stamps
    # of what it was built from. Nothing is kept if a file moved while it
    # built or if the binary does not answer as ruby does; the command
    # then runs under ruby. A second build waiting on the first one runs
    # under ruby too.
    def build
      Paths.mkdir_p(dir)
      File.open(File.join(dir, "lock"), File::RDWR | File::CREAT, 0o644) do |lock|
        return unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        return if current?

        before = stamps
        out = "#{binary}.#{Process.pid}"
        warn "zr: building the compiler with itself for faster builds, once for this zr (about a minute)"
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ok = system({ "ZR_COMPILED" => "0" }, RbConfig.ruby, File.join(Paths::ROOT, "exe/zr"), "build",
                    File.join(Paths::ROOT, "exe/zr"), "-o", out, out: File::NULL)
        answers = ok && IO.popen({ "ZR_COMPILED" => "0" }, [out, "version"], &:read) ==
                        IO.popen({ "ZR_COMPILED" => "0" }, [RbConfig.ruby, File.join(Paths::ROOT, "exe/zr"), "version"], &:read)
        if answers && stamps == before
          File.rename(out, binary)
          Paths.write_atomic(manifest, Marshal.dump(before))
          warn format("zr: built the compiled compiler in %.0f s", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        else
          warn "zr: the compiled compiler did not build; ruby runs zr"
        end
      ensure
        File.unlink(out) if out && File.exist?(out)
      end
    end
  end
end
