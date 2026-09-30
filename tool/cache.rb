# frozen_string_literal: true

require_relative "lib/zr/dev"
require_relative "../lib/zr/cache"

module Zr
  module Dev
    # Commands that clean the runtime cache: the store of lib/zr/store.rb,
    # and the files that a zr wrote before it (lib/zr/cache.rb).
    #
    # The store gets a runtime object, a prelinked image, an eval support
    # object and a symbol table for each digest that this checkout builds.
    # The digest changes when any file under `lib` or `runtime` changes,
    # so old entries collect (9.5 GB after one week of work). It also gets
    # the code and the lowering of each unit, parsed trees, and the
    # binaries of `zr run` and the tiers.
    #
    #   zr-dev cache size             what is there, by kind
    #   zr-dev cache prune            all except the entries this checkout uses
    #   zr-dev cache prune --days 3   ... and keep entries used in 3 days
    #   zr-dev cache clear            everything, also this checkout's entries
    #
    # Each build names the entries it needs in a root of the store: the
    # runtime and eval support objects, their images and metadata, and the
    # code and lowering of this backend. A prune keeps them, whatever their
    # age, so the next build rebuilds nothing. `clear` removes them too;
    # use it when the disk is full. All other entries are made again on
    # demand.
    class Cache < Group
      summary "Show, prune or clear the runtime cache"

      commands({
        "size" => ["What the runtime cache holds, by kind", -> { Size }],
        "live" => ["Which files this checkout names, and whether they are built", -> { Live }],
        "prune" => ["Remove the files this checkout does not use", -> { Prune }],
        "clear" => ["Empty the runtime cache, whatever this checkout names", -> { Clear }]
      })

      # What the commands share: the files, and which of them this
      # checkout uses (lib/zr/cache.rb, which `zr cache` also uses).
      module Files
        module_function

        def all = Zr::Cache.all
        def live = Zr::Cache.live
        def megabytes(paths) = Zr::Cache.megabytes(paths)
        def kind(path) = Zr::Cache.kind(path)

        # wasmtime's cache of compiled modules. `zr-dev bench` and `zr run`
        # under Cranelift fill it (the tiers run Winch with the cache off).
        # These commands do not clean it, but `cache size` reports it,
        # because it can become large (67 GB on one machine). `wasmtime
        # config new` writes the file that sets its limit.
        def wasmtime = File.expand_path("~/Library/Caches/BytecodeAlliance.wasmtime")
      end

      class Size < Command
        summary "What the runtime cache holds, by kind"

        def run(_argv)
          files = Files.all
          files.group_by { |path| Files.kind(path) }.sort_by { |_, group| -Files.megabytes(group) }.each do |kind, group|
            puts format("%6d MB  %4d  %s", Files.megabytes(group), group.size, kind)
          end
          puts format("%6d MB  %4d  in all, of which %d MB is named by this checkout",
                      Files.megabytes(files), files.size, Files.megabytes(Files.live & files))
          return unless Dir.exist?(Files.wasmtime)

          held = Dir[File.join(Files.wasmtime, "**/*")].select { |path| File.file?(path) }
          puts format("%6d MB  %4d  wasmtime's own cache at %s; rm -r it, or bound it with `wasmtime config new`",
                      Files.megabytes(held), held.size, Files.wasmtime)
        end
      end

      class Live < Command
        summary "Which files this checkout names, and whether they are built"

        def run(_argv)
          Files.live.each { |path| puts format("%-5s %s", File.exist?(path) ? "have" : "want", File.basename(path)) }
        end
      end

      class Prune < Command
        summary "Remove the files this checkout does not use"
        usage "[--days N]"

        def options(o)
          o.on("--days N", Float, "also keep files touched in the last N days (default: ZR_CACHE_DAYS or 1)") { |v| @days = v }
        end

        def run(_argv)
          days = @days || Float(ENV.fetch("ZR_CACHE_DAYS", 1))
          sizes = Files.all.to_h { |path| [path, Zr::Cache.bytes([path])] }
          stale = Zr::Cache.prune(days: days)
          freed = stale.sum { |path| sizes.fetch(path, 0) } / (1 << 20)
          puts format("swept %d file(s), %d MB; %d MB left", stale.size, freed, Files.megabytes(Files.all))
        end
      end

      class Clear < Command
        summary "Empty the runtime cache, whatever this checkout names"

        def run(_argv)
          freed = Files.megabytes(Files.all)
          files = Zr::Cache.clear
          puts format("cleared %d file(s), %d MB", files.size, freed)
        end
      end
    end
  end
end
