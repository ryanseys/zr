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
    # Regexp::Onig, the regular expression compiler (runtime/core/regexp/onig).
    # Each file defines what the next file reads.
    ONIG_NAMES = %w[
      regexp/unicode_tables regexp/onig/syntax regexp/onig/errors regexp/onig/encoding_tables
      regexp/onig/encoding regexp/onig/encoding_unicode regexp/onig/encoding_multibyte
      regexp/onig/node regexp/onig/lexer regexp/onig/parser regexp/onig/tune regexp/onig/optimize
      regexp/onig/compile regexp/onig/program regexp/onig
    ].freeze
    # The core library files, in the order their toplevels run: a module
    # before the classes that include it. An `os/` name is a file of the OS
    # layer, under runtime/core/os/<os>/. It gives each OS's values for the
    # constants that the next portable file uses, in ruby's order.
    CORE_NAMES = (%w[
      module warning redefinitions encodings transcode cjk exception enumerable enumerator comparable integer bignum
      array hash range struct unicode string converter iso2022 ruled emoji kernel float proc binding
      format os/errno os/io_constants io io_buffer os/process_constants process signal env
      os/file_constants file argf data os/clock_constants gc random thread builtin_lines trace_point
      monitor time set ractor marshal pack
    ] + ONIG_NAMES + %w[
      regexp_pattern regexp pathname rational complex objectspace rubyvm box
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
      cli.rb
      native/link.rb native/link/darwin.rb native/link/static.rb native/toolchain.rb
      obj/jit.rb obj/jit/fiddle.rb
      obj/macho/block.rb obj/macho/executable.rb obj/macho/libsystem.rb obj/macho/prelink.rb obj/macho/skeleton.rb
    ].map { |name| File.join(__dir__, name) }.freeze

    # The compiler files that drive zr but that neither a build nor a link
    # loads: the caches of whole runs and of zr's own files, the server, the
    # compiled compiler's checks, `zr doctor` and `zr cache`. An edit to one
    # of them rebuilt the runtime (16 s, and eval support too), although no
    # output can depend on it. `compiler_digest_test.rb` checks that a build
    # and a link load none of them.
    DRIVER_ONLY = %w[
      cache/janitor.rb cache/run.rb doctor.rb server.rb
    ].map { |name| File.join(__dir__, name) }.freeze

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
      "backend/wasm" => ->(target) { target.arch == :wasm32 },
      "obj/macho" => ->(target) { target.object_format == :macho },
      "obj/elf" => ->(target) { target.object_format == :elf }
    }.freeze

    # The sources of `target` under this process's path root. The object
    # keeps the compiler's digest, which reads every compiler file.
    def self.for(target = Target.default) = (@all ||= {})[[target.triple, Paths.root]] ||= new(target)

    # The cache file of a runtime's symbol table, its wanted symbols and its
    # kernel's description (`Runtime#cached`).
    def self.symbols_path(runtime_digest) = Cache::Store.path(:meta, "#{runtime_digest}-symbols")

    # The cache file that lists the files the gem prelude loads, for the
    # digest `of` the runtime's other sources (`Runtime#gem_prelude_files`).
    def self.gem_prelude_list(of) = Cache::Store.path(:meta, "#{of}-gem-prelude")

    # The ledger is on in a checkout, and anywhere with `ZR_LEDGER=1`.
    def self.ledger? = Config.current.ledger.nil? ? Paths.checkout? : Config.current.ledger

    attr_reader :target

    def initialize(target)
      @target = target
      @compiler_digest = nil
    end

    # The kernel files: the portable kernel, then its OS layer, then its
    # architecture layer.
    def kernel_files
      Dir[File.join(Paths::RUNTIME, "kernel/*.rb")].sort +
        Dir[File.join(Paths::RUNTIME, "kernel/os/#{target.os_layer}/*.rb")].sort +
        Dir[File.join(Paths::RUNTIME, "kernel/arch/#{target.arch_layer}/*.rb")].sort
    end

    # The core library files, in the order their toplevels run.
    def core_files
      layer = target.os_layer
      CORE_NAMES.map do |name|
        File.join(Paths::RUNTIME, name.start_with?("os/") ? "core/os/#{layer}/#{name.delete_prefix("os/")}.rb" : "core/#{name}.rb")
      end
    end

    # The source files of the runtime, and the compiler files that lower
    # them.
    def sources = kernel_files + core_files + compiler_files

    # The compiler's files that can reach the runtime object.
    def compiler_files
      (Dir[File.join(__dir__, "**/*.rb")].sort - LINK_ONLY - DRIVER_ONLY).reject do |path|
        name = path.delete_prefix("#{__dir__}/")
        PER_TARGET.any? { |prefix, wants| name.start_with?(prefix) && !wants.call(target) }
      end
    end

    # The digest of the compiler files (part of the runtime's).
    def compiler_digest = @compiler_digest ||= Digests.sources(target, compiler_files)

    # The digest of what code outside the runtime object takes from the
    # runtime: the compiler files that lower it, the kernel's description
    # (the constants, layouts, signatures and effects that it bakes in), and
    # the symbol table (each name's id, and the count of sites). Eval support
    # and a program's units call the core only by name and by send, so an
    # edit to a core or kernel body that changes none of these keeps them.
    # Nil when the runtime's symbol table is not cached.
    def abi_digest(runtime_digest)
      rows = JSON.parse(File.read(RuntimeSources.symbols_path(runtime_digest)))
      Digest::SHA256.new.tap do |d|
        d << "abi 1\0" << compiler_digest << "\0" << rows.fetch("description") << "\0"
        rows.fetch("names").each { |name| d << (name ? "+#{name}" : "-") << "\0" }
        d << rows.fetch("sites").to_s
      end.hexdigest
    rescue JSON::ParserError, KeyError, SystemCallError
      nil
    end

    # The digest of what eval support takes from the runtime besides the ids
    # of the names it uses: the compiler, the kernel's description, where its
    # own ids start (the size of the runtime's table, with its pads) and the
    # count of the runtime's sites. The metadata of eval support lists the
    # runtime names it used, and a build keeps it while the runtime's table
    # still has each of them at its id (`EvalSupport#meta`). A new runtime
    # name that eval support does not use keeps it. Nil when the runtime's
    # symbol table is not cached.
    def eval_digest(runtime_digest)
      rows = JSON.parse(File.read(RuntimeSources.symbols_path(runtime_digest)))
      Digest::SHA256.hexdigest(["eval 1", compiler_digest, rows.fetch("description"), rows.fetch("names").size,
                                rows.fetch("sites")].join("\0"))
    rescue JSON::ParserError, KeyError, SystemCallError
      nil
    end

    # The ledger of the runtime's symbol ids (`Runtime#ledger`), and its
    # bytes, or nil when there is none or the ledger is off.
    def ledger_path = Cache::Store.path(:meta, "#{Cache::Store.key("ledger", target.triple)}-ledger")

    def ledger_text
      return nil unless RuntimeSources.ledger?

      path = ledger_path
      File.exist?(path) ? File.binread(path) : nil
    end

    # `Runtime#digest` without the compiler: from the sources and the cached
    # gem prelude list. Nil when that list is not cached; then only a build
    # knows the digest.
    def runtime_digest
      files = sources
      list = RuntimeSources.gem_prelude_list(Digests.sources(target, files))
      return nil unless File.exist?(list)

      prelude = JSON.parse(File.read(list))
      return nil unless prelude.all? { |file| File.file?(file) }

      Digests.with_ledger(Digests.sources(target, files + prelude), ledger_text)
    rescue JSON::ParserError, SystemCallError
      nil
    end
  end
end
