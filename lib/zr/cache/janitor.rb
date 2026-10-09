# frozen_string_literal: true

require_relative "../paths"
require_relative "store"
require_relative "../version"

module Zr
  module Cache
    # The runtime cache (`Paths.cache`), as `zr cache` and
    # `zr doctor` see it. Almost all of it is the store (lib/zr/cache/store.rb):
    # a runtime object, a prelinked image and eval support for each digest
    # that a zr builds, code packs, lowerings, parsed trees, and the
    # binaries that `zr run` and the program tests keep. The digest changes with
    # every file under lib/, so old entries collect: 9.5 GB
    # after one week of work in a checkout, and some hundred MB for each
    # release that a user installs.
    #
    # A clean keeps the entries that a fresh root of the store names
    # (`live`), whatever their age, so the next build rebuilds nothing.
    # All other entries are made again on demand.
    module Janitor
      module_function

      # A binary that the server gave a client to run (lib/zr/server.rb).
      # The client removes it after the run, so an older one is left over.
      SERVED_HOURS = 1

      # Each entry of the store (a file, or a directory for `run` and
      # `code`), and each binary that the server left.
      #: () -> Array[String]
      def all = Store.entries.map(&:path) + served

      #: () -> Array[String]
      def served
        young = Time.now - (SERVED_HOURS * 3600)
        Dir[File.join(Paths.cache, "served", "*")].select { |path| File.file?(path) && File.mtime(path) < young }
      end

      # The entries that this zr uses: each entry that a fresh root of the
      # store names. A build writes its roots: the runtime and eval support
      # objects, their images and metadata, and the code and lowering
      # entries of the backend.
      #: () -> Array[String]
      def live = Store.rooted_paths

      # The entries that the roots of `target` name.
      #: (Target target) -> Array[String]
      def live_for(target) = Store.rooted_paths(prefix: "#{target.triple}-")

      #: (Array[String] paths) -> Integer
      def bytes(paths) = paths.sum { |path| File.directory?(path) ? Store.tree_bytes(path) : File.size?(path).to_i }
      #: (Array[String] paths) -> Integer
      def megabytes(paths) = bytes(paths) / (1 << 20)

      # The store's kind of the entry at `path` (lib/zr/cache/store.rb), or
      # "served".
      #: (String path) -> String?
      def kind(path)
        store = "#{Store.dir}/"
        path.start_with?(store) ? path.delete_prefix(store).split("/").first : "served"
      end

      # Deletes the entries that this zr does not use and that were not used
      # in the last `days`, and the binaries that the server left. Returns
      # the paths it deleted.
      #: (?days: Integer | Float) -> Array[String]
      def prune(days: 0) = Store.clean(days: days).map(&:path) + remove(served)

      # Deletes the whole cache, also the entries this zr uses. Returns the
      # paths it deleted.
      #: () -> Array[String]
      def clear
        files = all
        Store.clear
        remove(served)
        files
      end

      #: (Array[String] paths) -> Array[String]
      def remove(paths) = paths.each { |path| Paths.remove(path) }

      # The most GB that an installed zr keeps in its cache before a build
      # prunes it (`ZR_CACHE_MAX_GB`, default 5; 0 turns the limit off).
      #: () -> Float
      def limit_gb = Config.current.cache_max_gb

      # How often a build measures the cache. A measure stats every entry
      # (tens of thousands of parsed trees), so a build does it at most once
      # a day.
      CHECK_EVERY = 86_400

      # After a build of an installed zr: removes the binaries that the
      # server left, then evicts the entries used longest ago that no root
      # names until the store is under the limit. A checkout cleans its own cache
      # with `zr cache clean`; the quotas of `run` and `binary` hold in
      # both.
      #: () -> void
      def trim
        return if Paths.checkout? || limit_gb <= 0

        stamp = File.join(Paths.cache, ".measured")
        return if File.exist?(stamp) && Time.now - File.mtime(stamp) < CHECK_EVERY

        Paths.write_atomic(stamp, "")
        remove(served)
        Store.evict(limit: limit_gb * (1 << 30))
      rescue SystemCallError
        nil # a cache that cannot be measured or cleaned does not stop a build
      end
    end
  end
end
