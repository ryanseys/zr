# frozen_string_literal: true

require_relative "../paths"

module Zr
  module Library
    # Where each part of the library that a program's `require` reads is.
    # Every other file asks here, so a move or a new ruby version changes
    # only this module. The names are RbConfig's and rubygems' where they
    # have one.
    #
    # Two kinds of code meet on the load path (Library::Roots.stdlib):
    #
    # - upstream code, as its authors ship it, in vendor/
    #   (tool/lib/zr/dev/vendored.rb): ruby's own library, the default and bundled
    #   gems, and the gems whose C zr ports;
    # - zr's own code under lib/zr/runtime/: the C halves in Ruby (EXT) and zr's
    #   own libraries (RUNTIME_LIB). It comes first, so a file there
    #   replaces an upstream file of its name.
    module Layout
      # The directory name of ruby's library version (RbConfig's
      # `ruby_version`): the same for each release of a series, with the
      # ABI version after a `+` for a preview (lib/zr/ruby_version.rb).
      API = RUBY_LIB_VERSION

      # The install prefix that holds ruby's library and gems, as
      # `zr-dev vendor` writes it.
      PREFIX = File.join(Paths::VENDOR, "ruby")
      # ruby's own library and the default gems.
      RUBYLIBDIR = File.join(PREFIX, "lib/ruby", API)
      # The gem home: gems/<name>-<version>/ and specifications/.
      GEM_DIR = File.join(PREFIX, "lib/ruby/gems", API)
      GEMS = File.join(GEM_DIR, "gems")
      SPECIFICATIONS = File.join(GEM_DIR, "specifications")
      # ruby's gem_prelude.rb, which every ruby runs at boot.
      GEM_PRELUDE = File.join(PREFIX, "gem_prelude.rb")

      # The license texts that no gem directory holds, and the record of
      # each source and each file of vendor/.
      LICENSES = File.join(Paths::VENDOR, "LICENSES")
      LOCK = File.join(Paths::VENDOR, "vendor.lock")
      # Upstream source files that no install has, which only the tools
      # read (prism's templates).
      SOURCES = File.join(Paths::VENDOR, "src")
      # A ruby's headers and rbconfig.rb for each target that is not this
      # host, laid out as its install prefix (Dev::Vendored::TARGET_RUBIES).
      TARGETS = File.join(Paths::VENDOR, "targets")

      # The directories below ROOT that hold upstream code a build reads.
      # Not all of vendor/: a checkout can keep a bundle in vendor/bundle.
      UPSTREAM = %w[vendor/ruby].freeze

      # The C halves of extensions, in Ruby. A file here is part of the
      # runtime, so it can call a kernel def through `Primitive`.
      EXT = File.join(Paths::RUNTIME, "ext")
      # zr's own libraries (zr/eval/runtime, zr/pretty_printer): part of the
      # runtime too, but no replacement of an upstream file.
      RUNTIME_LIB = File.join(Paths::RUNTIME, "lib")

      module_function

      # The directory of gem `name` at `version` in the gem home.
      def gem_root(name, version) = File.join(GEMS, "#{name}-#{version}")

      # The upstream source tree of `name` at `version` in SOURCES.
      def source(name, version) = File.join(SOURCES, "#{name}-#{version}")

      # The install prefix of the ruby for the target `triple`.
      def target_root(triple) = File.join(TARGETS, triple)

      # The rbconfig.rb of the ruby for the target `triple`, which finds its
      # headers from where it is.
      def target_rbconfig(triple) = File.join(target_root(triple), "lib/ruby", API, triple, "rbconfig.rb")

      # The OS layer of EXT for `target`.
      def ext_os(target) = File.join(EXT, "os", target.os_layer)
    end
  end
end
