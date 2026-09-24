# frozen_string_literal: true

require "digest/sha2"
require_relative "paths"

module Zr
  # A file's assembled machine code, kept between builds.
  #
  # A unit's code no longer carries anything the compile order decided:
  # its names come from the file it was written in, and its symbol ids
  # and literal slots are words the link fills (`Zr.number_symbols`). So
  # the same file compiled into any program writes the same bytes, and a
  # build can read those bytes back instead of making them again -- which
  # is where four fifths of a large build's time goes.
  #
  # **The cache fails closed.** Every input of a unit's bytes is in the
  # key, and a program whose numbers the key cannot hold is not cached at
  # all: one that measures coverage, where a def site's row comes from a
  # counter the whole program shares, and any file that activates a
  # refinement, where a `using` carries the row it took. Both are rare,
  # and both would be quietly wrong.
  #
  # One input is the other units' names. A `require` or an `autoload`
  # spells the entry of the unit it runs (`Zr::Lower#unit_entry`), and
  # that entry is the unit's file where the file is absolute and its
  # place in the program where it is not: a program compiled in another
  # directory, or with a file added before, names its units otherwise,
  # and a unit kept from the first would call an entry that nothing
  # defines -- or another file's. So the key holds every entry of the
  # program, and a program whose entries moved lowers its units again.
  # It could hold only the entries a unit spells, and let the rest of
  # a large program keep its units when one file is added; that is a
  # compile-speed item, not a correctness one.
  class UnitCache
    # The shape of what is kept. Raise it and every entry written by an
    # older zr is a miss, which is the cheapest way to retire one.
    VERSION = 2

    # The cache for `program`, or nil where this program is one no key
    # can describe. `entries` are the program's unit entries, in order.
    def self.for(program, dir:, runtime:, table:, entries:)
      return nil if program.coverable&.any?

      new(dir: dir, runtime: runtime, table: table, traced: program.traced ? 1 : 0, entries: entries)
    end

    def initialize(dir:, runtime:, table:, traced:, entries:)
      @dir = dir
      # `runtime` is the digest of everything that lowers and emits the
      # runtime for this target, and `table` names the symbol table a
      # unit's ids are fixed against -- the runtime's, or the road's
      # where the program carries one, which holds more names.
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

    # What this build made for `unit`, for the next one to read; nothing
    # while a source has moved under the build (`Zr.settled!`).
    def keep(unit, prefix, functions, data)
      key = key(unit, prefix) or return nil

      Zr.settled!
      Paths.write_atomic(path(key), Marshal.dump([functions, data]))
    rescue SystemCallError
      nil
    end

    private

    def path(key) = File.join(@dir, "unit-#{key}.marshal")

    # Every input of the unit's bytes, or nil where one of them is a
    # number this key cannot hold.
    def key(unit, prefix)
      return nil if unit.source.nil? || unit.activates

      Digest::SHA256.hexdigest([@stamp, prefix, unit.file, unit.internal ? 1 : 0, unit.hidden ? 1 : 0,
                                unit.source.b].join("\0"))
    end
  end
end
