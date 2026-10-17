# frozen_string_literal: true

require "digest/sha2"
require_relative "store"

module Zr
  module Cache
    # The machine code that a running program compiled, kept in the store
    # as kind `loaded`: of a file (`Eval::Compiler#compile_file`: a require
    # of a file that the build did not compile in, or a `load`), and of an
    # eval's string. The next run of a program on the same compiler maps
    # it and does not compile. A new process compiled for seconds before it
    # could start irb (fileutils and delegate eval strings as they load),
    # and each child ruby of a test suite is such a process.
    #
    # As a build's units (`Cache::Unit`), the code has only the kernel's
    # symbol ids. Its other names and its literal sites are pool words that
    # each process numbers from its own table (`SymbolNumbering.number`),
    # so a process that interned other names first gets correct code.
    #
    # **The cache fails closed.** The key is the compiler (`stamp`), the
    # trace flag, the path and the source. An entry also records what else
    # the code depends on, and a hit needs each to be the same now: the
    # digest of each other file that the compile read (the files that its
    # literal requires compiled in), and each answer of the gvar aliases
    # that the build asked about. The compiler keeps nothing for code that
    # numbers Coverage's counters or takes `using` entries, as a build's
    # cache does not.
    #
    # `ZR_CODE_CACHE=0` turns it off. Under `ZR_CODE_CACHE=verify` each hit
    # compiles too, and raises when the code differs.
    class Loaded
      # @rbs @stamp: String

      VERSION = 1

      # An entry: the code (`Obj::Unit`, unnumbered), the name of its
      # toplevel, error_highlight's spots of a file, the checks of a hit
      # (`files`: path to SHA-256; `aliases`: name to the old name), and an
      # eval's `[local count, using entry]` (nil for a file).
      # @rbs skip -- typed in sig/zr/cache/loaded.rbs
      Entry = Data.define(:unit, :top, :spots, :files, :aliases, :shape)

      # The cache, or nil when `ZR_CODE_CACHE=0`. `stamp` names the compiler
      # that a hit must have compiled with.
      #: (String stamp) -> Loaded?
      def self.for(stamp) = Config.current.code_cache == "0" ? nil : new(stamp)

      #: (String stamp) -> void
      def initialize(stamp)
        @stamp = stamp
      end

      #: () -> bool
      def verify? = Config.current.code_cache == "verify"

      # The key of the code of `parts`: what it is ("file" or "eval"), and
      # every input of its compile that the stamp does not cover.
      #: (*_ToS parts) -> String
      def key(*parts) = Store.key(VERSION, @stamp, *parts)

      # The entry under `key` when its checks hold now, else nil. `aliases`
      # answers a gvar alias as the build asks it.
      #: (String key, ^(Symbol) -> Symbol? aliases) -> Entry?
      def take(key, aliases)
        entry = Store.read(:loaded, key)
        entry if entry.is_a?(Entry) && current?(entry, aliases)
      end

      #: (String key, Entry entry) -> void
      def keep(key, entry)
        Store.write(:loaded, key, entry)
      rescue SystemCallError
        nil
      end

      private

      #: (Entry entry, ^(Symbol) -> Symbol? aliases) -> bool
      def current?(entry, aliases)
        entry.aliases.all? { |name, was| aliases.call(name) == was } &&
          entry.files.all? { |path, digest| File.file?(path) && Digest::SHA256.hexdigest(File.binread(path)) == digest }
      end
    end
  end
end
