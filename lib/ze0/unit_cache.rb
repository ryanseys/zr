# frozen_string_literal: true

require "digest"
require "fileutils"

module Ze0
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
  class UnitCache
    # The shape of what is kept. Raise it and every entry written by an
    # older ze0 is a miss, which is the cheapest way to retire one.
    VERSION = 1

    # The cache for `program`, or nil where this program is one no key
    # can describe.
    def self.for(program, dir:, runtime:, table:)
      return nil if program.coverable&.any?

      new(dir: dir, runtime: runtime, table: table, traced: program.traced ? 1 : 0)
    end

    def initialize(dir:, runtime:, table:, traced:)
      @dir = dir
      # `runtime` is the digest of everything that lowers and emits the
      # runtime for this target, and `table` names the symbol table a
      # unit's ids are fixed against -- the runtime's, or the road's
      # where the program carries one, which holds more names.
      @stamp = "#{VERSION}\0#{runtime}\0#{table}\0#{traced}"
    end

    # `[functions, data]` an earlier build left for `unit`, or nil.
    def take(unit, prefix)
      key = key(unit, prefix) or return nil

      bytes = File.binread(path(key))
      Marshal.load(bytes)
    rescue SystemCallError, TypeError, ArgumentError
      nil
    end

    # What this build made for `unit`, for the next one to read.
    def keep(unit, prefix, functions, data)
      key = key(unit, prefix) or return nil

      FileUtils.mkdir_p(@dir)
      tmp = "#{path(key)}.#{Process.pid}"
      File.binwrite(tmp, Marshal.dump([functions, data]))
      File.rename(tmp, path(key))
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
