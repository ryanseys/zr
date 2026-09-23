# frozen_string_literal: true

require "rbconfig"
require_relative "paths"

module Ze0
  # The compiler ze0 compiled, run in place of the one ruby runs: the
  # same code, the same answers (`rake stage2` holds it to that), and a
  # warm build takes less time under it.
  #
  # `exe/ze0` asks here first. The compiled compiler answers a build only
  # while every file it was built from is as it was then: the stamp of
  # each file under lib/, rt/, vendor/ and of exe/ze0, and the same list
  # of files. Anything else is a miss, and ruby runs the command. An
  # installed gem builds the compiled compiler at its first build and
  # says so; a checkout, whose files change all day, builds one only
  # under `ZE0_SELF=1` or `rake build:self`. `ZE0_SELF=0` never hands
  # the command over.
  module SelfHost
    # The commands a compiled compiler takes over. The others answer at
    # once under ruby.
    VERBS = %w[run build machine zr].freeze

    module_function

    def dir = File.join(Paths.cache, "self")
    def binary = File.join(dir, "ze0")
    def manifest = File.join(dir, "manifest.marshal")

    # The command goes to the compiled compiler when it is current, or
    # once one is built for a first build that may build it. Under the
    # compiled compiler itself, and for any other command, nothing
    # happens here.
    def hand_over(argv, env = ENV)
      return unless RbConfig::CONFIG["ruby_install_name"] != "ze0" && VERBS.include?(argv.first)
      return if env["ZE0_SELF"] == "0"

      build if !current? && (env["ZE0_SELF"] == "1" || !Paths.checkout?)
      exec(binary, *argv) if current?
    end

    # Every file a compiled compiler is built from, and its stamp.
    def sources
      [File.join(Paths::ROOT, "exe/ze0"), *Dir[File.join(Paths::ROOT, "{lib,rt,vendor}/**/*")]].select { |f| File.file?(f) }.sort
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
        warn "ze0: building the compiler with itself for faster builds, once for this ze0 (about a minute)"
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ok = system({ "ZE0_SELF" => "0" }, RbConfig.ruby, File.join(Paths::ROOT, "exe/ze0"), "build",
                    File.join(Paths::ROOT, "exe/ze0"), "-o", out, out: File::NULL)
        answers = ok && IO.popen({ "ZE0_SELF" => "0" }, [out, "version"], &:read) ==
                        IO.popen({ "ZE0_SELF" => "0" }, [RbConfig.ruby, File.join(Paths::ROOT, "exe/ze0"), "version"], &:read)
        if answers && stamps == before
          File.rename(out, binary)
          File.binwrite("#{manifest}.#{Process.pid}", Marshal.dump(before))
          File.rename("#{manifest}.#{Process.pid}", manifest)
          warn format("ze0: built the compiled compiler in %.0f s", Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
        else
          warn "ze0: the compiled compiler did not build; ruby runs ze0"
        end
      ensure
        File.unlink(out) if out && File.exist?(out)
      end
    end
  end
end
