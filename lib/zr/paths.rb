# frozen_string_literal: true

require_relative "config"
require_relative "binary"
require_relative "version"
require_relative "error"

module Zr
  # Where zr reads its sources and writes what it builds. ROOT is the
  # checkout or the installed gem. `lib/zr/runtime/` is under `lib/` and
  # `vendor/` is beside it in both; neither is on the host's load path. The host
  # loads a few namespaced files from them by path (Regexp::Onig,
  # Prism::Ruby).
  module Paths
    ROOT = File.expand_path("../..", __dir__)

    # The runtime that zr compiles into every program, in the kernel
    # subset and in ordinary Ruby. It is source that zr compiles, not code
    # of the compiler, although it is under lib/zr.
    RUNTIME = File.join(ROOT, "lib/zr/runtime")

    # The Ruby parts of extension gems, and ruby's own pure-Ruby
    # standard library.
    VENDOR = File.join(ROOT, "vendor")

    # A git checkout, or a worktree of one, where `.git` is a file. A
    # bundler git source (`gem "zr", git: ...`) is a clone too, but it is
    # an install: bundler puts it in `.../bundler/gems/zr-<revision>`.
    #: (?String root) -> bool
    def self.checkout?(root = ROOT)
      File.exist?(File.join(root, ".git")) && File.dirname(root).split(File::SEPARATOR).last(2) != %w[bundler gems]
    end

    # The root for the paths that a build writes (`zr build --path-root
    # DIR`), or nil to write each path as it is on this machine. A path
    # under zr's root or under the build's working directory becomes the
    # root plus its path below that directory. The longer prefix is tried
    # first. So two checkouts built with one root write the same bytes.
    # A relative path (often the main file) stays as given, as in ruby.
    #: () -> String?
    def self.root = Session.current.memo(:path_root) { nil }

    #: (String? root) -> void
    def self.root=(root)
      Session.current.set(:path_root, root&.then { |r| r == "/" ? "" : r.chomp("/") })
      Session.current.set(:path_prefixes, root && [ROOT, Dir.pwd].uniq.sort_by { |prefix| -prefix.size })
    end

    # `path` as a build writes it into its output.
    #: (String path) -> String
    def self.shown(path)
      root = self.root
      prefixes = Session.current.memo(:path_prefixes) { nil } #: Array[String]?
      return path unless root && prefixes && path.start_with?("/")

      prefixes.each do |prefix|
        next unless path == prefix || path.start_with?("#{prefix}/")

        shown = "#{root}#{path[prefix.size..]}"
        return shown.empty? ? "/" : shown
      end
      path
    end

    # The user's cache directory for zr: `XDG_CACHE_HOME` when it is
    # set, else the platform's own.
    #: () -> String
    def self.user_cache
      base = ENV["XDG_CACHE_HOME"]
      if base.nil? || base.empty?
        home = begin
          Dir.home
        rescue ArgumentError
          raise Missing, "HOME is not set, so zr has no cache directory. Set HOME, or set ZR_CACHE to a directory that you can write to."
        end
        base = File.join(home, RUBY_PLATFORM.include?("darwin") ? "Library/Caches" : ".cache")
      end
      File.join(base, "zr")
    end

    # A directory that zr needs and that this environment does not give.
    class Missing < StandardError
      include Error
    end

    # A cache that is not this user's alone. zr loads code from the files
    # of its cache and runs the binaries in it, so a user who can write
    # there can run code as each user of that cache.
    class Untrusted < StandardError
      include Error
    end

    # The cache directory for the runtime's build output (`ZR_CACHE`). A
    # checkout uses its own tmp/. An installed gem writes nothing under
    # itself. Its files are keyed on the digest of all their inputs: the
    # runtime sources and the compiler. Each bootstrap stage uses its own
    # cache, so it emits the runtime itself and does not read another
    # stage's output.
    #
    # Computed when a build calls it, not when this file loads. A program
    # with eval support links in this file but never builds. On wasi,
    # `getpwuid` has no wasm form, so reading the home directory at load
    # would stop the module before its first line.
    #: () -> String
    def self.cache
      Session.current.memo(:cache) { trusted!(Config.current.cache || (checkout? ? File.join(ROOT, "tmp/cache") : user_cache)) }
    end

    # `dir`, made with mode 0700 when it is missing. Raises Untrusted when
    # another user owns it or can write to it, or when a directory above
    # it lets every user rename it away (world-writable without the sticky
    # bit; /tmp has the bit). root may own it. WASI has no users.
    #: (String dir) -> String
    def self.trusted!(dir)
      return dir if RUBY_PLATFORM.include?("wasi")

      mkdir_p(dir, 0o700)
      stat = File.stat(dir)
      fix = "zr loads code from its cache, so the cache must be yours alone"
      unless stat.owned? || stat.uid.zero?
        raise Untrusted, "the cache #{dir} belongs to another user (uid #{stat.uid}). #{fix}: set ZR_CACHE to a directory of your own."
      end
      unless (stat.mode & 0o022).zero?
        mode = format("%04o", stat.mode & 0o7777)
        raise Untrusted, "other users can write to the cache #{dir} (mode #{mode}). " \
                         "#{fix}: run chmod go-w #{dir}, or set ZR_CACHE to a directory of your own."
      end
      above = File.dirname(File.expand_path(dir))
      loop do
        mode = File.stat(above).mode
        if (mode & 0o002).positive? && (mode & 0o1000).zero?
          raise Untrusted, "every user can write to #{above}, above the cache #{dir}. #{fix}: set ZR_CACHE to a directory of your own."
        end
        break if above == File.dirname(above)

        above = File.dirname(above)
      end
      dir
    end

    # The functions that the compiler needs from fileutils and tmpdir,
    # without those libraries. A compiled compiler loads a library when it
    # runs its first lines. fileutils defines its NoWrite, DryRun and
    # Verbose methods with a `module_eval` of a string each: about a
    # hundred eval compiles, half a second before a build starts.

    # Makes `dir` and each missing directory above it. `dir` itself gets
    # `mode` (less the umask); the directories above it get the default.
    #: (String dir, ?Integer mode) -> void
    def self.mkdir_p(dir, mode = 0o777)
      return if File.directory?(dir)

      mkdir_p(File.dirname(dir))
      Dir.mkdir(dir, mode)
    rescue Errno::EEXIST
      raise unless File.directory?(dir)
    end

    # Writes `bytes` to `path` through a temporary file and a rename, so
    # that another process never reads half a file. Returns `path`.
    #: (String path, String bytes) -> String
    def self.write_atomic(path, bytes)
      mkdir_p(File.dirname(path))
      fresh = "#{path}.#{Process.pid}.#{Thread.current.object_id}"
      begin
        File.binwrite(fresh, bytes)
        File.rename(fresh, path)
      ensure
        # A write that stopped (Ctrl-C, a full disk) leaves no part file.
        File.unlink(fresh) if File.exist?(fresh)
      end
      path
    end

    # Writes the file at `out` through a draft beside it: the block writes
    # the draft, then a rename puts it in place. So a build that stops
    # leaves the old file as it was, and a binary that runs from `out`
    # keeps its bytes. The draft has `out`'s own name, in a new directory
    # of its own, because a Mach-O code signature names the file
    # (Obj::MachO::Executable#signature) and the bytes must not depend on
    # the draft.
    #: [T] (String out) { (String draft) -> T } -> T
    def self.publish(out)
      raise Errno::EISDIR, out if File.directory?(out)

      dir = new_tmpdir(".zr-#{File.basename(out)}.", File.dirname(out))
      draft = File.join(dir, File.basename(out))
      result = yield draft
      File.rename(draft, out) if File.exist?(draft)
      result
    ensure
      remove(dir) if dir
    end

    # The mode of an executable that zr writes: 0755 less the umask, as a
    # new file gets.
    #: () -> Integer
    def self.exec_mode = 0o755 & ~File.umask

    # Copies `from` to `to` with its mode and times, as `FileUtils.cp`
    # with `preserve: true` does.
    #: (String from, String to) -> void
    def self.copy(from, to)
      IO.copy_stream(from, to)
      stat = File.stat(from)
      File.chmod(stat.mode & 0o7777, to)
      File.utime(stat.atime, stat.mtime, to)
    end

    # Runs the block while this process holds the lock of `path`, unless
    # `path` exists, and returns `path`. A second zr that builds the same
    # cache file waits for the first, then uses its file. `waiting` runs
    # before a wait.
    #: (String path, ?waiting: ^() -> void | nil) { () -> void } -> String
    def self.once(path, waiting: nil)
      return path if File.exist?(path)

      mkdir_p(File.dirname(path))
      File.open("#{path}.lock", File::RDWR | File::CREAT, 0o644) do |lock|
        unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          waiting&.call
          lock.flock(File::LOCK_EX)
        end
        yield unless File.exist?(path)
      end
      path
    end

    # The mtime (to the nanosecond) and size of the file at `path`, or
    # nil when there is no file. A change to either shows the file changed.
    #: (String path) -> [Rational, Integer]?
    def self.stamp(path)
      stat = File.stat(path)
      [stat.mtime.to_r, stat.size]
    rescue SystemCallError
      nil
    end

    # A new directory for the block, named as Dir.mktmpdir does
    # (`<prefix><date>-<pid>-<random>`; the test harness's sweep reads
    # the pid from the name). The block's end removes it and its contents.
    #: [T] (String prefix, ?String? root) { (String) -> T } -> T
    def self.tmpdir(prefix, root = nil)
      root ||= [ENV.fetch("TMPDIR", ""), "/tmp"].find { |dir| File.directory?(dir) && File.writable?(dir) }
      raise Missing, "zr found no temp directory that it can write to. Set TMPDIR to one." unless root

      dir = new_tmpdir(prefix, root)
      begin
        Session.current.set(:open_tmpdirs, open_tmpdirs + 1)
        yield dir
      ensure
        Session.current.set(:open_tmpdirs, open_tmpdirs - 1)
        remove(dir)
      end
    end

    # Makes a directory with a new name in `root`, and returns its path.
    #: (String prefix, String root) -> String
    def self.new_tmpdir(prefix, root)
      loop do
        name = File.join(root, "#{prefix}#{Time.now.strftime("%Y%m%d")}-#{Process.pid}-#{rand(0x100000000).to_s(36)}")
        begin
          Dir.mkdir(name, 0o700)
          return name
        rescue Errno::EEXIST
          nil
        end
      end
    end
    private_class_method :new_tmpdir

    #: () -> Integer
    def self.open_tmpdirs = Session.current.memo(:open_tmpdirs) { 0 }

    # Whether a `tmpdir` block runs now. A process that execs then would
    # leave the directory behind (`GcTuning.heavy!`).
    #: () -> bool
    def self.tmpdir_open? = open_tmpdirs.positive?

    # Removes `path` and, for a directory, all of its contents. It removes
    # a link and does not follow it.
    #: (String path) -> void
    def self.remove(path)
      if File.directory?(path) && !File.symlink?(path)
        Dir.children(path).each { |child| remove(File.join(path, child)) }
        Dir.rmdir(path)
      else
        File.unlink(path)
      end
    rescue Errno::ENOENT
      nil
    end
  end
end
