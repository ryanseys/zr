# frozen_string_literal: true

require "digest/sha2"
require "json"
require_relative "paths"
require_relative "target"

# The source files of the runtime and of the compiler that lowers it, and
# the digests of them that name the cache's files. A build loads all of
# zr; a check of a cache entry (`RunCache#hit`) loads only this file, so
# it costs the digests and not the compiler.
module Zr
  # The zr runtime: the kernel files, the core library written in Ruby on
  # top of them, and the data that the compiler lays out next to them.
  #
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

  # Loads Regexp::Onig under the host ruby, for the tools and tests that
  # check it against ruby's engine.
  def self.require_onig
    ONIG_NAMES.each { |name| require File.join(Paths::RUNTIME, "core/#{name}.rb") }
  end

  module_function

  # The kernel files of `target`'s runtime: the portable kernel, then its
  # OS layer, then its architecture layer.
  def kernel_files(target = Target.default)
    Dir[File.join(Paths::RUNTIME, "kernel/*.rb")].sort +
      Dir[File.join(Paths::RUNTIME, "kernel/os/#{target.os_layer}/*.rb")].sort +
      Dir[File.join(Paths::RUNTIME, "kernel/arch/#{target.arch_layer}/*.rb")].sort
  end

  # The core library files for `target`, in the order their toplevels
  # run.
  def core_files(target = Target.default)
    layer = target.os_layer
    CORE_NAMES.map do |name|
      File.join(Paths::RUNTIME, name.start_with?("os/") ? "core/os/#{layer}/#{name.delete_prefix("os/")}.rb" : "core/#{name}.rb")
    end
  end

  # The compiler files that no runtime object can depend on: the command
  # line, the linkers, and the images and processes that they write.
  # All other files under `lib` are in the digest, so a new compiler file
  # is included until someone adds it here. A stale runtime object gives
  # a wrong binary with no error.
  #
  # These files do change the link, so `link_digest` is part of the name
  # of the prelinked image.
  LINK_ONLY = %w[
    cli.rb
    native/link.rb native/link/darwin.rb native/link/static.rb native/toolchain.rb
    obj/jit.rb obj/jit/fiddle.rb
    obj/macho/block.rb obj/macho/executable.rb obj/macho/libsystem.rb obj/macho/prelink.rb obj/macho/skeleton.rb
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

  # The source files of `target`'s runtime, and the compiler files that
  # lower them.
  def sources(target = Target.default)
    kernel_files(target) + core_files(target) + compiler_files(target)
  end

  # The compiler's files that can reach `target`'s runtime object.
  def compiler_files(target = Target.default)
    (Dir[File.join(__dir__, "**/*.rb")].sort - LINK_ONLY).reject do |path|
      name = path.delete_prefix("#{__dir__}/")
      PER_TARGET.any? { |prefix, wants| name.start_with?(prefix) && !wants.call(target) }
    end
  end

  # One digest of the LINK_ONLY files. A cache that the link writes
  # includes this digest in its name, with its other inputs.
  def link_digest
    @link_digest ||= Digest::SHA256.new.tap do |d|
      LINK_ONLY.each { |path| d << path << "\0" << File.binread(path) }
    end.hexdigest
  end

  # The digest that names a runtime's cache files: the target, the path
  # root, and each of `files` with its bytes (`bytes` has the ones that a
  # build already read, so it hashes what it lowered).
  def source_digest(target, files, bytes = {})
    Digest::SHA256.new.tap do |d|
      d << target.triple << "\0"
      d << "root\0" << Paths.root << "\0" if Paths.root
      files.each { |path| d << path << "\0" << (bytes[path] || File.binread(path)) }
    end.hexdigest
  end

  # The key of an eval support object: the runtime's digest and the bytes
  # of each file (`EvalSupport#files_key`). `bytes` has the ones that a
  # build already read.
  def eval_files_key(runtime_digest, files, bytes = {})
    Digest::SHA256.new.tap do |d|
      d << runtime_digest
      files.each do |path|
        d << path << "\0" << (bytes[path] || (File.exist?(path) ? File.binread(path) : ""))
      end
    end.hexdigest
  end

  # The cache file that lists the files the gem prelude loads, for the
  # digest `of` the runtime's other sources (`Runtime#gem_prelude_files`).
  def gem_prelude_list(of) = File.join(Paths.cache, "gem-prelude-#{of}.json")

  # `Runtime#digest` without the compiler: from the sources and the cached
  # gem prelude list. Nil when that list is not cached; then only a build
  # knows the digest.
  def runtime_digest(target = Target.default)
    files = sources(target)
    list = gem_prelude_list(source_digest(target, files))
    return nil unless File.exist?(list)

    prelude = JSON.parse(File.read(list))
    return nil unless prelude.all? { |file| File.file?(file) }

    source_digest(target, files + prelude)
  rescue JSON::ParserError, SystemCallError
    nil
  end
end
