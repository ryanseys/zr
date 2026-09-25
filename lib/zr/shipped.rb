# frozen_string_literal: true

require "rbconfig"
require_relative "paths"
require_relative "version"
require_relative "library_digests"

module Zr
  # A compiled compiler that a platform gem ships, at
  # `exe/<platform>/zr` (docs/how-to/release.md). A platform gem is
  # installed, not built on the user's machine, so its file stamps say
  # nothing about the build. Its manifest gives the content digest of the
  # sources that the binary was built from instead:
  #
  #     version 0.1.0
  #     ruby 4.0.6
  #     platform arm64-darwin
  #     digest <SHA-256 of the sources below the root and the pinned libraries>
  #
  # The first build reads every source to check the digest, then keeps
  # the file stamps that it checked in the user's cache. A later build
  # compares only the stamps, as for a binary that zr built itself.
  module Shipped
    module_function

    # The manifest of the binary for this host, or nil if this install
    # ships none. Only a platform gem has an `exe/<platform>/` directory.
    def manifest_path
      Dir[File.join(Paths::ROOT, "exe/*/zr.manifest")].find { |path| host?(File.basename(File.dirname(path))) }
    end

    def binary = manifest_path&.then { |path| File.join(File.dirname(path), "zr") }

    # Whether the gem platform `name` (`arm64-darwin`) runs on this host.
    # The build of a native binary is for aarch64 only.
    def host?(name)
      cpu, os = name.split("-", 2)
      %w[arm64 aarch64].include?(cpu) && RbConfig::CONFIG["host_cpu"].match?(/\A(arm64|aarch64)/) &&
        RbConfig::CONFIG["host_os"].start_with?(os.to_s.split("-").first)
    end

    # The fields of the manifest at `path`, by name.
    def read(path)
      File.readlines(path, chomp: true).to_h { |line| line.split(" ", 2) }
    end

    # The SHA-256 of the files of `files` below the root, each by its
    # path below the root and its bytes, and of the pinned libraries'
    # digests. The same tree gives the same digest wherever it is
    # installed. The library tree is elsewhere on each machine, and
    # `Libraries` checks its files against these digests.
    def digest(files)
      require "digest"
      d = Digest::SHA256.new
      files.each do |f|
        next unless f.start_with?("#{Paths::ROOT}/")

        d << f.delete_prefix("#{Paths::ROOT}/") << "\0" << File.binread(f) << "\0"
      end
      Libraries::DIGESTS_BY_NAME.sort.each { |name, sha| d << name << "\0" << sha << "\0" }
      d.hexdigest
    end

    # The manifest text for a binary built from `files` for `platform`.
    def manifest(files, platform)
      "version #{VERSION}\nruby #{RUBY}\nplatform #{platform}\ndigest #{digest(files)}\n"
    end

    # Whether the shipped binary was built from `files` (the compiler's
    # sources below the root, `CompiledCompiler.program`) by this version.
    def current?(files, stamps)
      path = manifest_path or return false
      fields = read(path)
      return false unless fields["version"] == VERSION && fields["ruby"] == RUBY && File.executable?(binary)
      return true if verified == stamps

      (fields["digest"] == digest(files)).tap { |ok| remember(stamps) if ok }
    rescue SystemCallError
      false
    end

    # The stamps of the sources at the last digest check that passed.
    def verified_path
      require "digest"
      File.join(Paths.user_cache, "shipped-#{VERSION}-#{Digest::SHA256.hexdigest(Paths::ROOT)[0, 12]}", "verified.marshal")
    end

    def verified
      Marshal.load(File.binread(verified_path))
    rescue SystemCallError, TypeError, ArgumentError, EOFError
      nil
    end

    def remember(stamps)
      Paths.mkdir_p(File.dirname(verified_path))
      Paths.write_atomic(verified_path, Marshal.dump(stamps))
    rescue SystemCallError
      nil
    end
  end
end
