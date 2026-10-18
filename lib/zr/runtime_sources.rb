# frozen_string_literal: true

require "digest/sha2"
require "json"
require_relative "config"
require_relative "digests"
require_relative "paths"
require_relative "cache/store"
require_relative "target"

module Zr
  # The source files of one target's runtime and of the compiler that
  # lowers it, and the digests of them that name the cache's entries. A
  # build loads all of zr; a check of a cache entry (`Cache::Run#hit`)
  # loads only this file, so it costs the digests and not the compiler.
  #
  # The runtime is the kernel files, the core library written in Ruby on
  # top of them, and the data that the compiler lays out next to them.
  class RuntimeSources
    # @rbs @compiler_digest: String?
    # @rbs @sources: Array[String]?

    # Regexp::Onig, the regular expression compiler (lib/zr/runtime/core/regexp/onig).
    # Each file defines what the next file reads.
    ONIG_NAMES = %w[
      regexp/unicode_tables regexp/onig/syntax regexp/onig/errors regexp/onig/encoding_tables
      regexp/onig/encoding regexp/onig/encoding_unicode regexp/onig/encoding_multibyte
      regexp/onig/node regexp/onig/lexer regexp/onig/parser regexp/onig/tune regexp/onig/optimize
      regexp/onig/compile regexp/onig/program regexp/onig
    ].freeze
    # The core library files, in the order their toplevels run: a module
    # before the classes that include it. An `os/` name is a file of the OS
    # layer, under lib/zr/runtime/core/os/<os>/. It gives each OS's values for the
    # constants that the next portable file uses, in ruby's order.
    CORE_NAMES = (%w[
      module warning redefinitions encodings transcode cjk exception enumerable enumerator comparable integer bignum os/integer_constants
      array hash range struct string symbol encoding converter iso2022 ruled emoji kernel float proc binding
      format c_format os/errno os/io_constants io io_buffer os/process_constants process signal ruby_version env
      os/file_constants file argf data os/clock_constants gc random thread builtin_lines trace_point
      monitor time set ractor marshal pack
    ] + ONIG_NAMES + %w[
      regexp_pattern regexp pathname rational complex objectspace rubyvm yarv_insns box rubyopt aliases
    ]).freeze

    # The compiler files that no runtime object can depend on: the command
    # line, the linkers, and the images and processes that they write.
    # All other files under `lib` are in the digest, so a new compiler file
    # is included until someone adds it here. A stale runtime object gives
    # a wrong binary with no error.
    #
    # These files do change the link, so `Digests.link` is part of the name
    # of the prelinked image.
    LINK_ONLY = %w[
      cli.rb cli/command.rb cli/errors.rb cli/help.rb cli/options.rb cli/refusals.rb cli/runner.rb
      cli/commands/cache.rb cli/commands/compile.rb cli/commands/diff.rb cli/commands/doctor.rb cli/commands/gems.rb cli/commands/help.rb
      cli/commands/inspect.rb cli/commands/version.rb
      ext/c_api.rb native/link.rb native/link/darwin.rb native/link/static.rb native/toolchain.rb
      obj/jit.rb obj/jit/fiddle.rb
      obj/macho/block.rb obj/macho/executable.rb obj/macho/image.rb obj/macho/libsystem.rb obj/macho/prelink.rb
      obj/macho/skeleton.rb
    ].map { |name| File.join(__dir__, name) }.freeze

    # The compiler files that drive zr but that neither a build nor a link
    # loads: the caches of whole runs and the janitor of the cache, the
    # server, `zr diff`'s runner (which zr-dev's probe, gem trials and
    # fuzzer share), `zr doctor`, the reader of ruby's switches, the printer of
    # `--dump=parsetree`, the kernel's lock plan (lib/zr/lock_plan.rb, which
    # only a test reads), the host machine that runs the kernel on CRuby
    # (machine/host.rb and each file under machine/host/), and the RbConfig
    # that the host ruby loads for an extconf.rb of another target (the
    # extension build key covers it). An edit to one of them rebuilt the
    # runtime (16 s, and eval support too), although no output can depend
    # on it. `compiler_digest_test.rb` checks that a build and a link load
    # none of them, and that it lists each compiler file that they do not
    # load.
    DRIVER_ONLY = (%w[cache/janitor.rb cache/run.rb cli/parse_tree.rb cli/ruby_options.rb diff.rb doctor.rb ext/target_rbconfig.rb
                      lock_plan.rb machine/host.rb server.rb server/client.rb]
                     .map { |name| File.join(__dir__, name) } +
                   Dir[File.join(__dir__, "machine/host/**/*.rb")]).sort.freeze

    # The compiler files that belong to one target: an instruction set's
    # backend, and an object format's writer. A runtime object for a
    # different target contains no byte of them, so they are not in other
    # targets' digests. For example, a wasm backend edit does not rebuild
    # the native runtime.
    #
    # As with LINK_ONLY, the list is by name and the default is to include
    # a file. A directory not listed here is in every target's digest.
    PER_TARGET = {
      "backend/aarch64" => ->(target) { target.arch == :aarch64 },
      "backend/x86_64" => ->(target) { target.arch == :x86_64 },
      "obj/relocs/x86_64" => ->(target) { target.arch == :x86_64 },
      "backend/wasm" => ->(target) { target.arch == :wasm32 },
      "obj/macho" => ->(target) { target.object_format == :macho },
      "obj/elf" => ->(target) { target.object_format == :elf }
    }.freeze #: Hash[String, ^(Target) -> bool]

    # The sources of `target` under this process's path root. The object
    # keeps the compiler's digest, which reads every compiler file.
    #: (?Target target) -> RuntimeSources
    def self.for(target = Target.default) = Session.current.memo([:runtime_sources, target.triple, Paths.root]) { new(target) }

    # The cache file of a runtime's symbol table, its wanted symbols and its
    # kernel's description (`Runtime#cached`).
    #: (String runtime_digest) -> String
    def self.symbols_path(runtime_digest) = Cache::Store.path(:meta, "#{runtime_digest}-symbols")

    # The cache file that lists the files the gem prelude loads, for the
    # digest `of` the runtime's other sources (`Runtime#gem_prelude_files`).
    #: (String of) -> String
    def self.gem_prelude_list(of) = Cache::Store.path(:meta, "#{of}-gem-prelude")

    # The rows of the symbol table of the runtime of `runtime_digest`
    # (`symbols_path`), read once per process, or nil when it is not
    # cached or does not parse. The rows are frozen: every reader shares
    # them.
    #: (String runtime_digest) -> Hash[String, untyped]?
    def self.symbol_rows(runtime_digest)
      Session.current.memo([:symbol_rows, runtime_digest]) { JSON.parse(File.read(symbols_path(runtime_digest)), freeze: true) }
    rescue JSON::ParserError, SystemCallError
      nil
    end

    # Drops the rows read for `runtime_digest`, after a build wrote them.
    #: (String runtime_digest) -> void
    def self.forget_symbol_rows(runtime_digest) = Session.current.forget([:symbol_rows, runtime_digest])

    attr_reader :target #: Target

    #: (Target target) -> void
    def initialize(target)
      @target = target
      @compiler_digest = nil
      @sources = nil
    end

    # The kernel files: the portable kernel, then the POSIX layer that the
    # OSes with POSIX threads share (not wasm), then its OS layer and that
    # layer's part for the architecture, then its architecture layer,
    # then the C API for a target that runs native C extensions (not wasm).
    #: () -> Array[String]
    def kernel_files
      native = target.arch != :wasm32
      Dir[File.join(Paths::RUNTIME, "kernel/*.rb")].sort +
        (native ? Dir[File.join(Paths::RUNTIME, "kernel/os/posix/*.rb")].sort : []) +
        Dir[File.join(Paths::RUNTIME, "kernel/os/#{target.os_layer}/*.rb")].sort +
        Dir[File.join(Paths::RUNTIME, "kernel/os/#{target.os_layer}/arch/#{target.arch_layer}/*.rb")].sort +
        Dir[File.join(Paths::RUNTIME, "kernel/arch/#{target.arch_layer}/*.rb")].sort +
        (native ? Dir[File.join(Paths::RUNTIME, "kernel/capi/*.rb")].sort : [])
    end

    # The core library files, in the order their toplevels run. An OS
    # file comes from the OS layer for the architecture (`linux-x86_64`)
    # when that layer has it, else from the OS layer.
    #: () -> Array[String]
    def core_files
      layer = target.os_layer
      CORE_NAMES.map do |name|
        next File.join(Paths::RUNTIME, "core/#{name}.rb") unless name.start_with?("os/")

        file = "#{name.delete_prefix("os/")}.rb"
        own = File.join(Paths::RUNTIME, "core/os/#{layer}-#{target.arch_layer}", file)
        File.exist?(own) ? own : File.join(Paths::RUNTIME, "core/os/#{layer}", file)
      end
    end

    # The source files of the runtime, and the compiler files that lower
    # them.
    #: () -> Array[String]
    def sources = @sources ||= (kernel_files + core_files + compiler_files).freeze

    # The compiler's files that can reach the runtime object. The runtime
    # (`Paths::RUNTIME`) is under lib/zr too, but it is what the compiler
    # compiles: `kernel_files` and `core_files` list it.
    #: () -> Array[String]
    def compiler_files
      (Dir[File.join(__dir__, "**/*.rb")].sort - LINK_ONLY - DRIVER_ONLY).reject do |path|
        name = path.delete_prefix("#{__dir__}/")
        path.start_with?("#{Paths::RUNTIME}/") || PER_TARGET.any? { |prefix, wants| name.start_with?(prefix) && !wants.call(target) }
      end
    end

    # The digest of the compiler files (part of the runtime's).
    #: () -> String
    def compiler_digest = @compiler_digest ||= Digests.sources(target, compiler_files)

    # The digest of what code outside the kernel takes from the runtime:
    # the compiler files that lower it, the kernel's description (the
    # constants, layouts, signatures and effects that it bakes in), and the
    # kernel's names (the only ids in such code). Eval support and a
    # program's units call the core only by name, and the link numbers every
    # other name, so no core edit changes their code. Nil when the
    # runtime's symbol table is not cached.
    #: (String runtime_digest) -> String?
    def abi_digest(runtime_digest)
      rows = RuntimeSources.symbol_rows(runtime_digest) or return nil
      Digest::SHA256.new.tap do |d|
        d << "abi 2\0" << compiler_digest << "\0" << rows.fetch("description") << "\0"
        rows.fetch("names").first(rows.fetch("kernel")).each { |name| d << (name ? "+#{name}" : "-") << "\0" }
      end.hexdigest
    rescue KeyError
      nil
    end

    # The digest of what eval support's object takes from the runtime: its
    # ABI (`abi_digest`), and the runtime's table (each name's id, and the
    # count of sites), which numbers eval support's data. Nil when the
    # runtime's symbol table is not cached.
    #: (String runtime_digest) -> String?
    def eval_digest(runtime_digest)
      abi = abi_digest(runtime_digest) or return nil
      rows = RuntimeSources.symbol_rows(runtime_digest) or return nil
      Digest::SHA256.new.tap do |d|
        d << "eval 2\0" << abi << "\0" << rows.fetch("sites").to_s
        rows.fetch("names").each { |name| d << (name ? "\0+#{name}" : "\0-") }
      end.hexdigest
    rescue KeyError
      nil
    end

    # `Runtime#digest` without the compiler: from the sources and the cached
    # gem prelude list. Nil when that list is not cached; then only a build
    # knows the digest.
    #: () -> String?
    def runtime_digest
      files = sources
      stamps = files.to_h { |path| [path, Paths.stamp(path)] }
      list = RuntimeSources.gem_prelude_list(Digests.sources(target, files, stamps))
      return nil unless File.exist?(list)

      prelude = JSON.parse(File.read(list))
      return nil unless prelude.all? { |file| File.file?(file) }

      Digests.sources(target, files + prelude, stamps)
    rescue JSON::ParserError, SystemCallError
      nil
    end
  end
end
