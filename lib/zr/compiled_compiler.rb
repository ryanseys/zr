# frozen_string_literal: true

require "rbconfig"
require_relative "paths"
require_relative "version"
require_relative "self_built"
require_relative "shipped"

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
    # checkout, else the binary that a platform gem ships (`Shipped`),
    # else a directory of the user's cache for this version and this
    # install. An installed gem writes nothing under itself, and two
    # installed versions do not share a binary.
    def binary
      return ENV["ZR_BINARY"] if ENV["ZR_BINARY"]
      return File.join(Paths::ROOT, "bin/zr") if Paths.checkout?

      shipped || File.join(install_dir, "zr")
    end

    # The binary that this install's platform gem ships, or nil.
    def shipped = Shipped.binary

    def install_dir
      require "digest"
      File.join(Paths.user_cache, "self-#{VERSION}-#{Digest::SHA256.hexdigest(Paths::ROOT)[0, 12]}")
    end

    # The compiler as a SelfBuilt program: `exe/zr`, built from lib/,
    # runtime/, vendor/ and the library tree. The library tree is
    # included, because a changed pin refers to a different tree.
    def program = SelfBuilt.new(entry: "exe/zr", binary: binary, dirs: %w[lib runtime vendor]) { library_files }

    def manifest = program.manifest
    def sources = program.sources
    def stamps(files = sources) = program.stamps(files)

    # A shipped binary is current when its sources have the digest in its
    # manifest; a built one, when their stamps are those in its manifest.
    def current?
      return program.current? unless shipped?

      files = sources
      Shipped.current?(files, stamps(files))
    end

    # Whether `binary` is the one that a platform gem ships. zr never
    # builds over it.
    def shipped? = !ENV["ZR_BINARY"] && !Paths.checkout? && !shipped.nil?

    # The variable that `CLI.tune!` sets when it starts zr again with the
    # collector's limits. It says that this process already decided to
    # keep the command, so the new process does not check every source
    # file again. `hand_over` deletes it, so the program never sees it.
    HANDED = "ZR_HANDED"

    # Sends the command to the compiled compiler when it is current. If
    # this build is permitted to build one, it builds it first. Does
    # nothing inside the compiled compiler or for other commands.
    def hand_over(argv, env = ENV)
      return if env.delete(HANDED)
      return if Zr.compiled? || !VERBS.include?(argv.first)
      return if env["ZR_COMPILED"] == "0"
      # A stand-in that `ZR_BINARY` names can run on any host.
      return unless runnable? || env["ZR_BINARY"]

      # One check of every source file: `current?` stats about two
      # thousand files and reads the manifest.
      current = current?
      if builds?(argv, env, current: current)
        build
        current = current?
      end
      # The compiled compiler has no rubygems, so this ruby resolves a
      # library pin again for it.
      exec({ "ZR_HOST_RUBY" => RbConfig.ruby }, binary, *argv) if current
    end

    # Whether this host can run the compiled compiler: it is a binary for
    # the host's own target, which the host must also be able to link.
    # On any other host (x86_64 Linux, an Intel Mac), ruby runs zr.
    def runnable?
      require_relative "target"
      host = Target.host
      !host.nil? && host.outputs.include?(:native) && host.linkable?
    end

    # Whether this command builds the compiled compiler first: the binary
    # is stale, the install permits a build, the last build of these same
    # sources did not fail, and the command compiles a file. A help
    # request or a usage error never starts the build.
    def builds?(argv, env = ENV, current: current?)
      return false if current || shipped?
      return false unless env["ZR_COMPILED"] == "1" || !Paths.checkout?
      return false if env["ZR_COMPILED"] != "1" && program.failed?
      return false if argv.any? { |word| %w[-h --help].include?(word) }

      argv.drop(1).any? { |word| !word.start_with?("-") && word.end_with?(".rb") && File.file?(word) }
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

    # Builds the compiled compiler with ruby from this tree. It keeps
    # nothing if the binary's `zr version` differs from ruby's. Then ruby
    # runs the command.
    def build
      began = nil
      # Without the ledger (Runtime#ledger), the binary's symbol ids come
      # from its sources only, as a release's must.
      quiet = { "ZR_COMPILED" => "0", "ZR_LEDGER" => "0" }
      announce = lambda do
        warn "zr: building the compiler with itself, once for this zr"
        began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      built = program.build(env: quiet, started: announce) do |out|
        IO.popen(quiet, [out, "version"], &:read) == IO.popen(quiet, [RbConfig.ruby, program.entry, "version"], &:read)
      end
      return unless began

      if built
        warn format("zr: built the compiled compiler in %.0f s", Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)
      else
        # Ruby runs zr from now on. The next build tries again only when
        # a source changes, or under `ZR_COMPILED=1`.
        program.fail!
        warn "zr: the compiled compiler did not build; ruby runs zr"
      end
    end
  end
end
