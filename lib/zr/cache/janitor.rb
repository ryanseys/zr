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

      # Each entry of the store (a file, or a directory for `run` and
      # `code`).
      #: () -> Array[String]
      def all = Store.entries.map(&:path)

      # The crash logs (CLI::Errors.crash_log) older than `days`.
      #: (?days: Integer | Float) -> Array[String]
      def crashes(days: 30)
        old = Time.now - (days * 86_400)
        Dir[File.join(Paths.cache, "crash", "*.log")].select { |path| File.mtime(path) < old }
      end

      #: (Array[String] paths) -> Array[String]
      def remove(paths) = paths.each { |path| Paths.remove(path) }

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
      # nil for a path outside the store.
      #: (String path) -> String?
      def kind(path)
        store = "#{Store.dir}/"
        path.delete_prefix(store).split("/").first if path.start_with?(store)
      end

      # Deletes the entries that this zr does not use and that were not used
      # in the last `days`, and the crash logs older than 30 days. Returns
      # the paths it deleted.
      #: (?days: Integer | Float) -> Array[String]
      def prune(days: 0) = Store.clean(days: days).map(&:path) + remove(crashes)

      # Deletes the whole cache, also the entries this zr uses. Returns the
      # paths it deleted.
      #: () -> Array[String]
      def clear
        files = all
        Store.clear
        files + remove(crashes(days: 0))
      end

      # The most GB that an installed zr keeps in its cache before a build
      # prunes it (`ZR_CACHE_MAX_GB`, default 5; 0 turns the limit off).
      #: () -> Float
      def limit_gb = Config.current.cache_max_gb

      # How often a build measures the cache. A measure stats every entry
      # (tens of thousands of parsed trees), so a build does it at most once
      # a day.
      CHECK_EVERY = 86_400

      # After a build of an installed zr: evicts the entries used longest
      # ago that no root names until the store is under the limit. A checkout cleans its own cache
      # with `zr cache clean`; the quotas of `run` and `binary` hold in
      # both.
      #: () -> void
      def trim
        return if Paths.checkout? || limit_gb <= 0

        stamp = File.join(Paths.cache, ".measured")
        return if File.exist?(stamp) && Time.now - File.mtime(stamp) < CHECK_EVERY

        Paths.write_atomic(stamp, "")
        remove(crashes)
        Store.evict(limit: limit_gb * (1 << 30))
      rescue SystemCallError
        nil # a cache that cannot be measured or cleaned does not stop a build
      end
    end
  end
end
