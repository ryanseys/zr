# frozen_string_literal: true

module Ze0
  # Where ze0 reads its sources and writes what it builds. ROOT is the
  # checkout or the installed gem: `rt/` and `vendor/` sit beside `lib/`
  # in both, and neither is ever on the host's load path.
  module Paths
    ROOT = File.expand_path("../..", __dir__)

    # The runtime ze0 compiles into every program, in kernel Ruby and
    # ordinary Ruby.
    RT = File.join(ROOT, "rt")

    # The Ruby halves of extension gems, and ruby's own pure-Ruby
    # standard library.
    VENDOR = File.join(ROOT, "vendor")

    # A git checkout, or a worktree of one, where `.git` is a file.
    def self.checkout? = File.exist?(File.join(ROOT, ".git"))

    # The root a build writes paths under (`ze0 build --path-root=STR`),
    # or nil, which writes each path as it is on this machine. A path
    # under ze0's own root or under the directory the build runs in is
    # written as the root plus its path below that directory, the longer
    # of the two first; so two checkouts built with one root write the
    # same bytes. A path given relative, as a main file often is, stays
    # as it was given, as ruby answers it.
    def self.root = @root

    def self.root=(root)
      @root = root&.then { |r| r == "/" ? "" : r.chomp("/") }
      @prefixes = root && [ROOT, Dir.pwd].uniq.sort_by { |prefix| -prefix.size }
    end

    # `path` as a build writes it into what it makes.
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

    # The library tree (lib/ze0/libraries.rb) is written as the layout
    # it replaced, so a build under a root names the same paths on any
    # machine, wherever its gems are.
    def self.libraries
      return [] unless defined?(Libraries)

      @libraries ||= [[Libraries.root, "vendor/lib"], *Libraries::APART.zip(Libraries.apart).map { |name, dir| [dir, "vendor/gems/#{name}/lib"] }]
    end

    # The user's cache directory for ze0: `XDG_CACHE_HOME` when it is
    # set, else the platform's own.
    def self.user_cache
      base = ENV["XDG_CACHE_HOME"]
      if base.nil? || base.empty?
        base = File.join(Dir.home, RUBY_PLATFORM.include?("darwin") ? "Library/Caches" : ".cache")
      end
      File.join(base, "ze0")
    end

    # Where the runtime's built forms live. A checkout keeps them in its
    # own tmp/; an installed gem writes nothing under itself.
    #
    # Found when a build asks, and never as this file loads. A program
    # that evals carries the eval road, the road carries this file, and
    # that program will never build anything. Reading the home directory
    # there cost a program its whole run on a target that has none: on
    # wasi `getpwuid` has no wasm form, so the module stopped before its
    # first line.
    def self.cache = @cache ||= ENV["ZE0_CACHE"] || (checkout? ? File.join(ROOT, "tmp/rt") : File.join(user_cache, "rt"))

    # The two things the compiler asks of fileutils and tmpdir, without
    # them: a compiled compiler loads a library as it runs its first
    # lines, and fileutils defines its NoWrite, DryRun and Verbose
    # methods with a `module_eval` of a string each -- some hundred
    # compiles through the eval road, half a second before a build
    # starts.

    # `dir` and every directory above it that is not there yet.
    def self.mkdir_p(dir)
      return if File.directory?(dir)

      mkdir_p(File.dirname(dir))
      Dir.mkdir(dir)
    rescue Errno::EEXIST
      raise unless File.directory?(dir)
    end

    # A fresh directory for the block, named as Dir.mktmpdir names one
    # (`<prefix><date>-<pid>-<random>`, which the test harness's sweep
    # reads the maker's pid from), and removed with what it holds after.
    def self.scratch(prefix, root = nil)
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

    # `path` and, for a directory, everything under it; a link is
    # removed and not followed.
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
