# frozen_string_literal: true

require "rbconfig"
require_relative "paths"
require_relative "version"

module Zr
  # The compiler that zr compiled, run in place of the one that ruby runs.
  # It is the same code with the same output (`zr-dev stage 2` checks this),
  # and a warm build is faster with it.
  #
  # `exe/zr` calls this module first. The compiled compiler runs a build
  # only if its source files are unchanged: the same list of files, and
  # the same file stamp for each file under lib/, runtime/, vendor/, the
  # library tree, and exe/zr. Otherwise ruby runs the command. An
  # installed gem builds the compiled compiler at its first build and
  # tells the user. A checkout, whose files change frequently, builds one
  # only with `ZR_COMPILED=1` or `rake build:self`, as `bin/zr`. With `ZR_COMPILED=0`,
  # ruby always runs the command.
  module CompiledCompiler
    # The commands that a compiled compiler runs. Ruby runs all others.
    VERBS = %w[run build machine].freeze

    module_function

    # Where the compiled compiler is: `ZR_BINARY`, else `bin/zr` in a
    # checkout, else a directory of the user's cache for this version and
    # this install. An installed gem writes nothing under itself, and two
    # installed versions do not share a binary.
    def binary
      ENV["ZR_BINARY"] || (Paths.checkout? ? File.join(Paths::ROOT, "bin/zr") : File.join(install_dir, "zr"))
    end

    def install_dir
      require "digest"
      File.join(Paths.user_cache, "self-#{VERSION}-#{Digest::SHA256.hexdigest(Paths::ROOT)[0, 12]}")
    end

    # The file stamps of the sources the binary was built from, and the
    # lock that one build holds. Both are beside the binary.
    def manifest = "#{binary}.manifest"
    def lock_path = "#{binary}.lock"

    # Sends the command to the compiled compiler when it is current. If
    # this build is permitted to build one, it builds it first. Does
    # nothing inside the compiled compiler or for other commands.
    def hand_over(argv, env = ENV)
      return if Zr.compiled? || !VERBS.include?(argv.first)
      return if env["ZR_COMPILED"] == "0"

      build if !current? && (env["ZR_COMPILED"] == "1" || !Paths.checkout?)
      # The compiled compiler has no rubygems, so this ruby resolves a
      # library pin again for it.
      exec({ "ZR_HOST_RUBY" => RbConfig.ruby }, binary, *argv) if current?
    end

    # Every source file of a compiled compiler. The library tree is
    # included, because a changed pin refers to a different tree.
    def sources
      [File.join(Paths::ROOT, "exe/zr"), *Dir[File.join(Paths::ROOT, "{lib,runtime,vendor}/**/*")], *library_files].select { |f| File.file?(f) }.sort
    end

    # The files of the library tree, found by ruby's rubygems when the
    # manifest is stale. If the tree does not resolve, this returns a
    # placeholder path. Ruby then runs the build and reports the cause.
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

    # Builds the compiled compiler with ruby from this tree, and records
    # the file stamps of its sources. It keeps nothing if a file changed
    # during the build, or if the binary's output differs from ruby's.
    # Then ruby runs the command. A second build that waits for the lock
    # also runs under ruby.
    def build
      Paths.mkdir_p(File.dirname(binary))
      File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
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
