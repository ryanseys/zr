# frozen_string_literal: true

require_relative "paths"
require_relative "stdlib"

module Zr
  # The pure-Ruby library that a program's `require` reads: zr's standard
  # library (stdlib/), which is ruby 4.0.7's own library as a stock ruby
  # installs it (`zr-dev gen stdlib` writes it). zr compiles its files
  # into the program, and never loads them itself. A build reads no gem of
  # the host, so it needs no gem but zr, and two machines build the same
  # bytes.
  #
  # The gems with a C part are not here: zr owns them (lib/zr/ports.rb).
  module Libraries
    # ruby's own library and the default gems, as `rubylibdir` holds them.
    LIB = File.join(Paths::ROOT, "stdlib/lib/ruby/4.0.0")

    # Where the bundled gems are installed, each in its own directory.
    GEMS = File.join(Paths::ROOT, "stdlib/lib/ruby/gems/4.0.0/gems")

    module_function

    # The directory of ruby's own library and the default gems.
    def root = roots.first

    # The lib directory of each bundled gem, in Stdlib::BUNDLED's order.
    def apart = roots.last

    # The lib directory of the bundled gem `name`.
    def lib_of(name) = apart.fetch(Stdlib::BUNDLED.keys.index(name) || raise(KeyError, "no bundled gem #{name}"))

    def roots
      @roots ||= carried || [LIB, Stdlib::BUNDLED.map { |name, version| File.join(GEMS, "#{name}-#{version}", "lib") }]
    end

    # A program that includes the compiler uses the directories from its
    # build, because it can run on a machine with no zr. Only a build
    # with eval support writes them (Zr.load_tables): the roots of
    # `Hir::Build.stdlib`, ruby's library first and the bundled gems
    # last. Other compiled compilers find stdlib/ beside themselves.
    def carried
      return nil unless Zr.compiled? && defined?(::Zr::Eval::Runtime)

      names = ::Zr::Eval::Runtime.library_roots
      names.size > Stdlib::BUNDLED.size ? [names.first, names.last(Stdlib::BUNDLED.size)] : nil
    end

    # Every file of the library, for a stamp of what a build can read.
    def files = Dir[File.join(Paths::ROOT, "stdlib/lib/**/*")].select { |path| File.file?(path) }
  end
end
