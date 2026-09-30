# frozen_string_literal: true

require "digest/sha2"
require_relative "../config"
require_relative "../paths"
require_relative "../settled"

module Zr
  # zr's caches between builds. `Store` keeps every entry on disk. Each
  # other cache is a kind of entry with its own key and build code
  # (`Parse`, `Unit`, `Lowering`, `Run`), and `Janitor` sizes and
  # cleans them.
  module Cache
    # The one content store of zr's caches, in `<cache>/store`. An entry is
    # a file or a directory at `<kind>/<first two characters of its key>/<key>`,
    # and it is made again on demand. This module owns the layout, the
    # keys, the reads and writes, the locks and the eviction, so each
    # cache is its kind, its key parts and its build code.
    #
    #   key = Store.key(stamp, file, source)
    #   Store.write(:unit, key, code)
    #   Store.read(:unit, key)      # => code, or nil on a miss
    #
    # Eviction removes the entries used longest ago. A read touches an
    # entry, at most once a day. A build names the entries that the next
    # build needs (the runtime object, eval support, the code of its
    # backend) in a root (`root`), and no eviction removes them while the
    # root is fresh.
    module Store
      # How an entry's value is kept. `:raw` is bytes, `:json` and
      # `:marshal` encode a value, and `:dir` is a directory that the
      # block of `write` fills.
      Kind = Data.define(:name, :codec, :ext, :quota_gb)

      KINDS = [
        Kind.new(:object, :raw, ".o", nil),       # runtime and eval support objects
        Kind.new(:image, :raw, ".bin", nil),      # prelinked images and skeletons
        Kind.new(:meta, :json, ".json", nil),     # symbol tables, gem prelude lists, eval meta
        Kind.new(:wasm, :marshal, ".marshal", nil),
        Kind.new(:gems, :marshal, ".marshal", nil),
        Kind.new(:parse, :raw, "", nil),          # Prism parse results (Parse encodes them)
        Kind.new(:unit, :marshal, ".marshal", nil),
        Kind.new(:lowering, :marshal, ".marshal", nil),
        Kind.new(:code, :dir, "", nil),           # packs of machine code, one directory per backend
        Kind.new(:run, :dir, "", 2),              # `zr run` binaries
        Kind.new(:binary, :raw, "", nil)          # program test binaries; quota from ZR_TEST_BINARIES_GB
      ].to_h { |kind| [kind.name, kind] }.freeze

      # A root older than this protects nothing: the zr that wrote it is
      # likely gone.
      ROOT_DAYS = 30
      # A read touches an entry only when its mtime is older than this.
      TOUCH_EVERY = 86_400

      # A key is a digest, and sometimes a suffix (`<digest>-symbols`). No
      # key names a path outside its kind.
      KEY = /\A[0-9A-Za-z_-][0-9A-Za-z_.-]+\z/

      Entry = Data.define(:kind, :key, :path, :bytes, :mtime)

      module_function

      def dir = File.join(Paths.cache, "store")

      # A key of `parts`: each part as a string, ended by a NUL, into one
      # SHA-256.
      def key(*parts)
        digest = Digest::SHA256.new
        parts.each { |part| digest << part.to_s << "\0" }
        digest.hexdigest
      end

      def kind(name) = KINDS.fetch(name)

      def path(name, key)
        raise ArgumentError, "not a store key: #{key.inspect}" unless KEY.match?(key)

        File.join(dir, name.to_s, key[0, 2], "#{key}#{kind(name).ext}")
      end

      # The value of the entry, or nil when there is none or it does not
      # decode.
      def read(name, key)
        file = path(name, key)
        value = decode(kind(name).codec, file)
        touch(file)
        value
      rescue StandardError # a missing file, a bad Marshal or JSON, an old class: a miss
        nil
      end

      # Writes the entry and returns its path. A `:dir` kind takes a block
      # that fills the directory it gets. Writes nothing when a source
      # changed during the build (`Zr.settled!` raises SourceChanged).
      def write(name, key, value = nil, &)
        file = path(name, key)
        codec = kind(name).codec
        if codec == :dir
          Zr.settled!
          return write_dir(file, &)
        end

        write_file(file, encode(codec, value))
      end

      # Writes `bytes` to the cache file at `path` atomically, so a parallel
      # build never reads half of it, and returns `path`. Every write of
      # the cache comes here, also of a file whose path a cache makes
      # itself. Writes nothing when a source changed during the build.
      def write_file(path, bytes)
        Zr.settled!
        Paths.write_atomic(path, bytes)
      end

      # Runs the block with the entry's path while this process holds the
      # entry's lock, unless the entry exists (`Paths.once`), and returns
      # the path. The block writes the file.
      def once(name, key, waiting: nil)
        file = path(name, key)
        Paths.once(file, waiting: waiting) { yield file }
        touch(file)
        file
      end

      # Records that the entries at `paths` (from `path`) are the ones that
      # root `name` needs. A root is replaced, not added to. A root that
      # has the same entries is only touched, so each build can call this.
      def root(name, paths)
        raise ArgumentError, "not a root name: #{name.inspect}" unless name.match?(/\A[\w.-]+\z/)

        lines = paths.compact.map { |path| "#{relative(path)}\n" }.uniq.sort.join
        file = File.join(dir, "roots", name)
        return touch(file, 0) if roots_of(file) == lines

        Zr.settled!
        Paths.write_atomic(file, lines)
      end

      # The entries that the root file `file` lists, or nil when it has none.
      def roots_of(file)
        File.binread(file)
      rescue SystemCallError
        nil
      end

      # The path of an entry below the store's directory (`object/ab/ab12….o`).
      def relative(path)
        top = "#{dir}/"
        raise ArgumentError, "not a store entry: #{path}" unless path.start_with?(top)

        path.delete_prefix(top)
      end

      # The path of each entry that a fresh root names (all roots, or those
      # whose name starts with `prefix`).
      def rooted_paths(prefix: nil) = rooted(prefix: prefix).map { |line| File.join(dir, line) }

      # The relative path of each entry that a fresh root names.
      def rooted(now = Time.now, prefix: nil)
        roots = File.join(dir, "roots")
        return [] unless File.directory?(roots)

        Dir.children(roots).flat_map do |name|
          next [] if prefix && !name.start_with?(prefix)

          file = File.join(roots, name)
          File.mtime(file) < now - (ROOT_DAYS * 86_400) ? [] : File.readlines(file, chomp: true)
        rescue SystemCallError
          []
        end.uniq
      end

      # Every entry of the kinds `names` (all kinds by default).
      def entries(names = KINDS.keys)
        names.map { |name| kind(name) }.flat_map do |kind|
          top = File.join(dir, kind.name.to_s)
          children(top).flat_map do |prefix|
            children(File.join(top, prefix)).filter_map do |base|
              file = File.join(top, prefix, base)
              next if base.include?(".lock") || base.match?(/\.\d+(\.\d+)?\z/) # a lock or a write in progress

              stat = File.stat(file)
              bytes = stat.directory? ? tree_bytes(file) : stat.size
              Entry.new(kind.name, base.delete_suffix(kind.ext), file, bytes, stat.mtime)
            rescue SystemCallError
              nil
            end
          end
        end
      end

      # The most bytes of kind `name`, or nil for no quota.
      def quota(name)
        gb = name == :binary ? Config.current.test_binaries_gb : kind(name).quota_gb
        gb && (gb * (1 << 30))
      end

      # Removes the entries used longest ago that no fresh root names, until
      # each kind is within its quota and all entries are within `limit`
      # bytes (nil: no limit). `kinds` limits the pass to those kinds: a
      # write of a kind with a quota evicts only that kind. Returns the
      # entries it removed.
      def evict(limit: nil, kinds: KINDS.keys, now: Time.now)
        all = entries(kinds)
        kept = rooted(now).to_h { |line| [line, true] }
        total = all.sum(&:bytes)
        by_kind = all.group_by(&:kind).transform_values { |list| list.sum(&:bytes) }
        removed = []
        all.sort_by(&:mtime).each do |entry|
          next if kept[relative(entry.path)]

          over = (limit && total > limit) || ((q = quota(entry.kind)) && by_kind[entry.kind] > q)
          next unless over

          Paths.remove(entry.path)
          total -= entry.bytes
          by_kind[entry.kind] -= entry.bytes
          removed << entry
        end
        removed
      end

      # Removes every entry that no fresh root names and that was not used
      # in the last `days`. Returns them.
      def clean(days: 0, now: Time.now)
        kept = rooted(now).to_h { |line| [line, true] }
        young = now - (days * 86_400)
        gone = entries.reject { |entry| kept[relative(entry.path)] || entry.mtime > young }.each { |entry| Paths.remove(entry.path) }
        orphan_locks.each { |lock| Paths.remove(lock) }
        gone
      end

      # The lock files (`once`) whose entry is not there: a build that
      # stopped, or an entry that a clean removed. The lock of an entry
      # that a build makes now goes too; a second build then waits on a new
      # lock, and at worst builds the entry again, which the atomic write
      # allows.
      def orphan_locks
        KINDS.each_key.flat_map do |name|
          top = File.join(dir, name.to_s)
          children(top).flat_map do |prefix|
            folder = File.join(top, prefix)
            children(folder).filter_map do |base|
              lock = File.join(folder, base)
              lock if base.end_with?(".lock") && !File.exist?(lock.delete_suffix(".lock"))
            end
          end
        end
      end

      # Removes the whole store.
      def clear = Paths.remove(dir)

      def children(dir)
        File.directory?(dir) ? Dir.children(dir) : []
      end

      # The bytes of every file below `dir`.
      def tree_bytes(dir) = Dir[File.join(dir, "**/*")].sum { |path| File.file?(path) ? File.size(path) : 0 }

      def touch(file, every = TOUCH_EVERY)
        now = Time.now
        File.utime(now, now, file) if File.mtime(file) < now - every
      rescue SystemCallError
        nil
      end

      # JSON loads on first use, so a store that holds no JSON costs nothing.
      def json
        require "json"
        JSON
      end

      def decode(codec, file)
        case codec
        when :raw then File.binread(file)
        when :json then json.parse(File.read(file))
        when :marshal then Marshal.load(File.binread(file))
        when :dir then File.directory?(file) ? file : raise(Errno::ENOENT, file)
        end
      end

      def encode(codec, value)
        case codec
        when :raw then value
        when :json then json.generate(value)
        when :marshal then Marshal.dump(value)
        end
      end

      # Fills a new directory with the block, then renames it to `file`. A
      # second writer that renames first wins; this one's copy goes.
      def write_dir(file)
        Paths.mkdir_p(File.dirname(file))
        fresh = "#{file}.#{Process.pid}.#{Thread.current.object_id}"
        Paths.remove(fresh)
        Dir.mkdir(fresh)
        yield fresh
        Zr.settled!
        Paths.remove(file)
        File.rename(fresh, file)
        file
      ensure
        Paths.remove(fresh) if fresh && File.exist?(fresh)
      end

      private_class_method :children, :touch, :json, :decode, :encode, :write_dir, :roots_of
    end
  end
end
