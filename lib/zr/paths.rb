# frozen_string_literal: true

require "rbconfig"
require_relative "config"

module Zr
  # Whether this process is a program that zr compiled (the compiled
  # compiler, or a program with eval support) and not CRuby. A zr binary
  # gives the same RUBY_ENGINE and RubyVM as ruby 4.0.7, but its RbConfig
  # gives zr as the interpreter (runtime/ext/rbconfig.rb).
  def self.compiled? = RbConfig::CONFIG["ruby_install_name"] == "zr"

  # Where zr reads its sources and writes what it builds. ROOT is the
  # checkout or the installed gem. `runtime/` and `vendor/` are beside
  # `lib/` in both, and neither is on the host's load path. The host
  # loads a few namespaced files from them by path (Regexp::Onig,
  # Prism::Ruby, zr_description).
  module Paths
    ROOT = File.expand_path("../..", __dir__)

    # The runtime that zr compiles into every program, in the machine
    # dialect and in ordinary Ruby.
    RUNTIME = File.join(ROOT, "runtime")

    # The Ruby parts of extension gems, and ruby's own pure-Ruby
    # standard library.
    VENDOR = File.join(ROOT, "vendor")

    # A git checkout, or a worktree of one, where `.git` is a file.
    def self.checkout? = File.exist?(File.join(ROOT, ".git"))

    # The root for the paths that a build writes (`zr build --path-root
    # DIR`), or nil to write each path as it is on this machine. A path
    # under zr's root or under the build's working directory becomes the
    # root plus its path below that directory. The longer prefix is tried
    # first. So two checkouts built with one root write the same bytes.
    # A relative path (often the main file) stays as given, as in ruby.
    def self.root = @root

    def self.root=(root)
      @root = root&.then { |r| r == "/" ? "" : r.chomp("/") }
      @prefixes = root && [ROOT, Dir.pwd].uniq.sort_by { |prefix| -prefix.size }
    end

    # `path` as a build writes it into its output.
    def self.shown(path)
      return path unless @root && path.start_with?("/")

      libraries.each do |prefix, as|
        return "#{@root}/#{as}#{path[prefix.size..]}" if path == prefix || path.start_with?("#{prefix}/")
      end
      @prefixes.each do |prefix|
        next unless path == prefix || path.start_with?("#{prefix}/")

        shown = "#{@root}#{path[prefix.size..]}"
        return shown.empty? ? "/" : shown
      end
      path
    end

    # The library tree (lib/zr/libraries.rb) is written as the vendor/
    # layout, so a build with a root gives the same paths on any machine,
    # wherever its gems are.
    def self.libraries
      return [] unless defined?(Libraries)

      @libraries ||= [[Libraries.root, "vendor/lib"], *Libraries::APART.zip(Libraries.apart).map { |name, dir| [dir, "vendor/gems/#{name}/lib"] }]
    end

    # The user's cache directory for zr: `XDG_CACHE_HOME` when it is
    # set, else the platform's own.
    def self.user_cache
      base = ENV["XDG_CACHE_HOME"]
      if base.nil? || base.empty?
        base = File.join(Dir.home, RUBY_PLATFORM.include?("darwin") ? "Library/Caches" : ".cache")
      end
      File.join(base, "zr")
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
    def self.cache = @cache ||= Config.current.cache || (checkout? ? File.join(ROOT, "tmp/cache") : user_cache)

    # The two functions that the compiler needs from fileutils and tmpdir,
    # without those libraries. A compiled compiler loads a library when it
    # runs its first lines. fileutils defines its NoWrite, DryRun and
    # Verbose methods with a `module_eval` of a string each: about a
    # hundred eval compiles, half a second before a build starts.

    # Makes `dir` and each missing directory above it.
    def self.mkdir_p(dir)
      return if File.directory?(dir)

      mkdir_p(File.dirname(dir))
      Dir.mkdir(dir)
    rescue Errno::EEXIST
      raise unless File.directory?(dir)
    end

    # Writes `bytes` to `path` through a temporary file and a rename, so
    # that another process never reads half a file. Returns `path`.
    def self.write_atomic(path, bytes)
      mkdir_p(File.dirname(path))
      fresh = "#{path}.#{Process.pid}.#{Thread.current.object_id}"
      File.binwrite(fresh, bytes)
      File.rename(fresh, path)
      path
    end

    # The mtime (to the nanosecond) and size of the file at `path`, or
    # nil when there is no file. A change to either shows the file changed.
    def self.stamp(path)
      stat = File.stat(path)
      [stat.mtime.to_r, stat.size]
    rescue SystemCallError
      nil
    end

    # A new directory for the block, named as Dir.mktmpdir does
    # (`<prefix><date>-<pid>-<random>`; the test harness's sweep reads
    # the pid from the name). The block's end removes it and its contents.
    def self.tmpdir(prefix, root = nil)
      root ||= [ENV.fetch("TMPDIR", ""), "/tmp"].find { |dir| File.directory?(dir) && File.writable?(dir) }
      dir = nil
      until dir
        name = File.join(root, "#{prefix}#{Time.now.strftime("%Y%m%d")}-#{Process.pid}-#{rand(0x100000000).to_s(36)}")
        begin
          Dir.mkdir(name, 0o700)
          dir = name
        rescue Errno::EEXIST
          nil
        end
      end
      yield dir
    ensure
      remove(dir) if dir
    end

    # Removes `path` and, for a directory, all of its contents. It removes
    # a link and does not follow it.
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
