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
    CACHE = ENV["ZE0_CACHE"] || (checkout? ? File.join(ROOT, "tmp/rt") : File.join(user_cache, "rt"))
  end
end
