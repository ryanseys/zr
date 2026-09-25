# frozen_string_literal: true

require "digest/sha2"
require_relative "paths"
require_relative "settled"

module Zr
  # A file's assembled machine code, kept between builds.
  #
  # A unit's code does not depend on the compile order. Its names come
  # from its source file, and its symbol ids and literal slots are words
  # that the link fills (`Zr.number_symbols`). So the same file gives the
  # same bytes in any program, and a build can read them back instead of
  # making them again. This saves most of a large build's time (about
  # four fifths).
  #
  # **The cache fails closed.** The key contains every input of a unit's
  # bytes. zr does not cache a program with numbers that the key cannot
  # contain: a program that measures coverage (a def site's entry comes
  # from a counter that the whole program shares), and a file that
  # activates a refinement (a `using` contains the entry it took). Both
  # are rare, and both would give wrong code without an error.
  #
  # The names of the other units are also an input. A `require` or an
  # `autoload` refers to the entry of the unit it runs
  # (`Zr::Lower#unit_entry`). That entry is the file path when the path
  # is absolute, else the unit's position in the program. So the key
  # contains every entry of the program, and a changed entry list lowers
  # all units again. A possible compile-speed improvement: key only on
  # the entries that a unit uses.
  class UnitCache
    # The format of the cache entries. Increase it to make every entry
    # from an older zr a miss.
    VERSION = 2

    # The cache for `program`, or nil if no key can describe this
    # program. `entries` are the program's unit entries, in order.
    def self.for(program, dir:, runtime:, table:, entries:)
      return nil if program.coverable&.any?

      new(dir: dir, runtime: runtime, table: table, traced: program.traced ? 1 : 0, entries: entries)
    end

    def initialize(dir:, runtime:, table:, traced:, entries:)
      @dir = dir
      # `runtime` is the digest of everything that lowers and emits the
      # runtime for this target. `table` identifies the symbol table that
      # fixes a unit's ids: the runtime's, or the eval support table when
      # the program links in eval support (it contains more names).
      @stamp = "#{VERSION}\0#{runtime}\0#{table}\0#{traced}\0#{Digest::SHA256.hexdigest(entries.join("\0"))}"
    end

    # `[functions, data]` an earlier build left for `unit`, or nil.
    def take(unit, prefix)
      key = key(unit, prefix) or return nil

      bytes = File.binread(path(key))
      Marshal.load(bytes)
    rescue SystemCallError, TypeError, ArgumentError
      nil
    end

    # Stores the code that this build made for `unit`, for the next build.
    # Stores nothing if a source changed during the build (`Zr.settled!`).
    def keep(unit, prefix, functions, data)
      key = key(unit, prefix) or return nil

      Zr.settled!
      Paths.write_atomic(path(key), Marshal.dump([functions, data]))
    rescue SystemCallError
      nil
    end

    private

    def path(key) = File.join(@dir, "unit-#{key}.marshal")

    # A digest of every input of the unit's bytes, or nil if one input is
    # a number that this key cannot contain.
    def key(unit, prefix)
      return nil if unit.source.nil? || unit.activates

      Digest::SHA256.hexdigest([@stamp, prefix, unit.file, unit.internal ? 1 : 0, unit.hidden ? 1 : 0,
                                unit.source.b].join("\0"))
    end
  end
end
