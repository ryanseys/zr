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
    # All other entries are made again on demand. The files that a zr wrote
    # before the store ("old layout") are never read again, and a clean
    # removes them.
    module Janitor
      module_function

      # The files that an older zr wrote, outside the store.
      OLD = "{*,binaries/*,parse/*,iseq/*,gems/*,run/*/*,code/*/*,core/*/*,eval-*/*/*}"

      # A binary that the server gave a client to run (lib/zr/server.rb).
      # The client removes it after the run, so an older one is left over.
      SERVED_HOURS = 1

      # Each entry of the store (a file, or a directory for `run` and
      # `code`), each file of the old layout, and each binary that the
      # server left.
      def all = Store.entries.map(&:path) + old + served

      # The spec harness's marks (`built-<digest>.ok`, test/support/built.rb)
      # are not old: they are empty, and a mark that goes makes the harness
      # check its runtime again.
      def old = Dir[File.join(Paths.cache, OLD)].select { |path| File.file?(path) && !File.basename(path).match?(/\Abuilt-.*\.ok\z/) }

      def served
        young = Time.now - (SERVED_HOURS * 3600)
        Dir[File.join(Paths.cache, "served", "*")].select { |path| File.file?(path) && File.mtime(path) < young }
      end

      # The compiled compilers and prebuilt binaries that older zr
      # versions kept in the user's cache (`self-*`, `shipped-*`). zr no
      # longer uses them. Each one is about 120 MB.
      def old_compilers = Dir[File.join(Paths.user_cache, "{self,shipped}-*")].select { |dir| File.directory?(dir) }

      # The entries that this zr uses: each entry that a fresh root of the
      # store names. A build writes its roots: the runtime and eval support
      # objects, their images and metadata, and the code and lowering
      # entries of the backend.
      def live = Store.rooted_paths

      # The entries that the roots of `target` name.
      def live_for(target) = Store.rooted_paths(prefix: "#{target.triple}-")

      def bytes(paths) = paths.sum { |path| File.directory?(path) ? Store.tree_bytes(path) : File.size?(path).to_i }
      def megabytes(paths) = bytes(paths) / (1 << 20)

      # The store's kind of the entry at `path` (lib/zr/cache/store.rb), or
      # "old layout" or "served".
      def kind(path)
        store = "#{Store.dir}/"
        return path.delete_prefix(store).split("/").first if path.start_with?(store)

        File.basename(File.dirname(path)) == "served" ? "served" : "old layout"
      end

      # Deletes the entries that this zr does not use and that were not used
      # in the last `days`, each file of the old layout, and the binaries
      # that the server left. Returns the paths it deleted.
      def prune(days: 0)
        gone = Store.clean(days: days).map(&:path)
        (gone + remove(old + served)).tap { remove_empty_dirs }
      end

      # Deletes the whole cache, also the entries this zr uses. Returns the
      # paths it deleted.
      def clear
        files = all
        Store.clear
        remove(old + served)
        remove_empty_dirs
        files
      end

      def remove(paths) = paths.each { |path| Paths.remove(path) }

      # The directories of the old layout, once empty.
      def remove_empty_dirs
        Dir[File.join(Paths.cache, "{binaries,parse,iseq,gems,served,run/*,run,code/*,code,core/*,core,eval-*/*,eval-*}")].each do |dir|
          Dir.rmdir(dir) if File.directory?(dir) && Dir.empty?(dir)
        rescue SystemCallError
          nil
        end
      end

      # The most GB that an installed zr keeps in its cache before a build
      # prunes it (`ZR_CACHE_MAX_GB`, default 5; 0 turns the limit off).
      def limit_gb = Config.current.cache_max_gb

      # How often a build measures the cache. A measure stats every entry
      # (tens of thousands of parsed trees), so a build does it at most once
      # a day.
      CHECK_EVERY = 86_400

      # After a build of an installed zr: removes the old layout, then
      # evicts the entries used longest ago that no root names until the
      # store is under the limit, then removes the compiled compilers of
      # other versions if it is still over. A checkout cleans its own cache
      # with `zr cache clean`; the quotas of `run` and `binary` hold in
      # both.
      def trim
        return if Paths.checkout? || limit_gb <= 0

        stamp = File.join(Paths.cache, ".measured")
        return if File.exist?(stamp) && Time.now - File.mtime(stamp) < CHECK_EVERY

        Paths.write_atomic(stamp, "")
        remove(old + served)
        limit = limit_gb * (1 << 30)
        Store.evict(limit: limit)
        old_compilers.each { |dir| Paths.remove(dir) } if bytes(Store.entries.map(&:path)) > limit
      rescue SystemCallError
        nil # a cache that cannot be measured or cleaned does not stop a build
      end
    end
  end
end
