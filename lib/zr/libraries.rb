# frozen_string_literal: true

require_relative "paths"
require_relative "stdlib"

module Zr
  # The pure-Ruby library that a program's `require` reads: ruby 4.0.7's
  # own library and bundled gems as a stock ruby installs them, in
  # vendor/ruby (`zr-dev vendor` writes it, lib/zr/vendor.rb). zr compiles
  # its files into the program, and never loads them itself. A build reads
  # no gem of the host, so it needs no gem but zr, and two machines build
  # the same bytes.
  #
  # The gems with a C part are zr's own (lib/zr/ports.rb).
  module Libraries
    module_function

    # The directory of ruby's own library and the default gems.
    def root = roots.first

    # The lib directory of each bundled gem, in Stdlib::BUNDLED's order.
    def apart = roots.last

    # The lib directory of the bundled gem `name`.
    def lib_of(name) = apart.fetch(Stdlib::BUNDLED.keys.index(name) || raise(KeyError, "no bundled gem #{name}"))

    def roots
      @roots ||= carried || [Layout::RUBYLIBDIR, Stdlib::BUNDLED.map { |name, version| File.join(Layout.gem_root(name, version), "lib") }]
    end

    # A program that includes the compiler uses the directories from its
    # build, because it can run on a machine with no zr. Only a build
    # with eval support writes them (`LoadTables`): the roots of
    # `Hir::Build.stdlib`, ruby's library first and the bundled gems
    # last. Other compiled compilers find vendor/ruby beside themselves.
    def carried
      return nil unless Host.compiled? && defined?(::Zr::Eval::Runtime)

      names = ::Zr::Eval::Runtime.library_roots
      names.size > Stdlib::BUNDLED.size ? [names.first, names.last(Stdlib::BUNDLED.size)] : nil
    end

    # Every file of the library, for a stamp of what a build can read.
    def files = Dir[File.join(Layout::PREFIX, "lib/**/*")].select { |path| File.file?(path) }
  end
end
