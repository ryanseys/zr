# frozen_string_literal: true

require "rbconfig"
require_relative "paths"

module Zr
  # A program of this checkout that zr compiles to a binary: the compiler
  # itself (`exe/zr` to `bin/zr`, lib/zr/compiled_compiler.rb) or the
  # tools (`tool/zr-dev.rb` to `bin/zr-dev`). The binary is current while
  # its sources are unchanged: the same list of files, and the same file
  # stamp for each. A stale binary must not run, because it holds the old
  # code. Its manifest (the stamps) and its lock are beside it.
  class SelfBuilt
    attr_reader :entry, :binary

    # `entry` is the program, `dirs` the directories below the root whose
    # files it is built from, and `extra` a block that gives more source
    # files (the compiler's library tree).
    def initialize(entry:, binary:, dirs:, &extra)
      @entry = File.join(Paths::ROOT, entry)
      @binary = binary
      @dirs = dirs
      @extra = extra
    end

    def manifest = "#{binary}.manifest"
    def lock_path = "#{binary}.lock"

    # The stamps of the sources of a build that failed. While the sources
    # keep these stamps, the build fails again, so no build starts.
    def failure = "#{binary}.failed"

    def failed?
      File.file?(failure) && Marshal.load(File.binread(failure)) == stamps
    rescue IOError, SystemCallError, TypeError, ArgumentError
      false
    end

    def fail!
      Paths.mkdir_p(File.dirname(failure))
      Paths.write_atomic(failure, Marshal.dump(stamps))
    end

    # Every source file, sorted.
    def sources
      # An empty brace would glob the whole root.
      files = @dirs.empty? ? [] : Dir[File.join(Paths::ROOT, "{#{@dirs.join(",")}}/**/*")]
      [entry, *files, *@extra&.call].select { |f| File.file?(f) }.sort
    end

    def stamps(files = sources)
      files.to_h { |f| [f, stamp(f)] }
    end

    def stamp(file)
      s = File.stat(file)
      [s.size, s.mtime.to_r, s.ctime.to_r, s.ino]
    end

    # A stale binary is the usual case in a checkout: a file it was built
    # from changed. So this first checks the manifest's own files, the
    # newest first, and stops at the first change. Only a binary whose
    # files are all the same pays for the list of every source (a new
    # file is also a change): 5 ms, not 48 ms, for each `zr run` of a
    # checkout with a stale bin/zr.
    def current?
      return false unless File.file?(binary) && File.executable?(binary) && File.file?(manifest)

      kept = Marshal.load(File.binread(manifest))
      changed = kept.sort_by { |_, was| -was[1] }.any? do |file, was|
        stamp(file) != was
      rescue SystemCallError
        true
      end
      !changed && kept == stamps
    rescue IOError, SystemCallError, TypeError, ArgumentError
      false
    end

    # Builds the binary with ruby from this tree, and records the file
    # stamps of its sources. It keeps nothing if a file changed during the
    # build, or if the block says that the new binary answers wrongly. The
    # block gets the binary's path, and runs once the binary is in place
    # and current, so the binary runs as it will run. A second build that
    # waits for the lock does nothing: it returns nil. `started` runs once
    # the build holds the lock. Returns true when the binary is current
    # after the build.
    def build(env: {}, started: nil)
      Paths.mkdir_p(File.dirname(binary))
      File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
        return nil unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        return true if current?

        started&.call
        before = stamps
        out = "#{binary}.#{Process.pid}"
        begin
          ok = system(env, RbConfig.ruby, File.join(Paths::ROOT, "exe/zr"), "build", entry, "-o", out, out: File::NULL)
          if ok && stamps == before
            File.rename(out, binary)
            Paths.write_atomic(manifest, Marshal.dump(before))
            [binary, manifest].each { |f| File.unlink(f) } if block_given? && !answers? { yield binary }
            File.unlink(failure) if current? && File.exist?(failure)
          end
        ensure
          File.unlink(out) if File.exist?(out)
        end
      end
      current?
    end

    private

    # The block's answer. A binary that this host cannot start (the wrong
    # architecture, the wrong format) answers wrongly, as does one that
    # raises.
    def answers?
      yield
    rescue SystemCallError, IOError
      false
    end
  end
end
