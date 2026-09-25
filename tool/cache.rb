# frozen_string_literal: true

require_relative "lib/zr/dev"

module Zr
  module Dev
    # Commands that clean the runtime cache.
    #
    # `tmp/cache` gets a runtime object, a prelinked image, an eval support
    # object and a symbol table for each digest that this checkout builds.
    # The digest changes when any file under `lib` or `runtime` changes,
    # so old entries collect (9.5 GB after one week of work).
    #
    # It also gets one `unit-<key>.marshal` for each file that a program
    # is built from (lib/zr/unit_cache.rb). Each is small, but a tier run
    # makes thousands. Each name contains the digest of the compiler that
    # made it, so a prune removes them with that compiler's other files.
    #
    #   zr-dev cache size             what is there, by kind
    #   zr-dev cache prune            all except the files this checkout uses
    #   zr-dev cache prune --days 3   ... and keep files touched in 3 days
    #   zr-dev cache clear            all files, also this checkout's files
    #
    # A prune keeps the files this checkout uses, whatever their age. Thus
    # the next build does not rebuild the runtime, eval support or the
    # images. `clear` removes those too; use it when the disk is full. All
    # other files are content-addressed and are made again on demand. A
    # wasm prelude and a gem prelude have names that come from more than
    # the runtime digest (the program's pending symbols, the files the
    # prelude loaded). Thus a prune keeps them by age only, and a prune
    # with 0 days makes the next wasm build rebuild its prelude.
    class Cache < Group
      summary "Show, prune or clear the runtime cache"

      commands({
        "size" => ["What the runtime cache holds, by kind", -> { Size }],
        "live" => ["Which files this checkout names, and whether they are built", -> { Live }],
        "prune" => ["Remove the files this checkout does not use", -> { Prune }],
        "clear" => ["Empty the runtime cache, whatever this checkout names", -> { Clear }]
      })

      # What the commands share: the files, and which of them this
      # checkout uses.
      module Files
        module_function

        def load!
          require_relative "../lib/zr/runtime"
          require_relative "../lib/zr/native/build"
        end

        # The cache files, the binaries that the spec tier keeps in the
        # cache, and the parsed trees (lib/zr/parse_cache.rb). There is one
        # parsed tree for each file ever parsed (about 70,000 after some
        # months). Their names come from the source only, so only age
        # shows which are not used.
        def all = Dir[File.join(Paths.cache, "{*,binaries/*,parse/*}")].select { |path| File.file?(path) }

        # wasmtime's cache of compiled modules. `zr-dev bench` and `zr run`
        # under Cranelift fill it (the tiers run Winch with the cache off).
        # These commands do not clean it, but `cache size` reports it,
        # because it can become large (67 GB on one machine). `wasmtime
        # config new` writes the file that sets its limit.
        def wasmtime = File.expand_path("~/Library/Caches/BytecodeAlliance.wasmtime")

        # The files that this checkout's compiler uses, for each target:
        # the runtime object, the eval support object and its meta file,
        # and the prelinked image of each. Only the meta file gives the key
        # of the eval support object.
        def live
          load!
          Target.all.flat_map { |target| live_for(target) }.compact.uniq
        rescue StandardError, ScriptError
          [] # if the compiler does not load, keep no file as live
        end

        def live_for(target)
          runtime = Zr.runtime(target)
          object = runtime.object_path
          metas = %w[jit walk].map { |kind| EvalSupport.meta_path(runtime, kind) }.select { |path| File.exist?(path) }
          evals = metas.filter_map { |meta| eval_object(meta) }
          sets = [[object], *evals.map { |eval| [object, eval] }]
          [object, *metas, *evals, *sets.map { |set| Native::Build.prelink_path(set) },
           *sets.map { |set| Native::Build.skeleton_path(set) }] + Dir[File.join(Paths.cache, "*-#{runtime.digest}.*")]
        end

        # The eval support object. Only its meta file gives its path.
        def eval_object(meta)
          require "json"
          key = JSON.parse(File.read(meta)).fetch("key") if File.exist?(meta)
          key && EvalSupport.object_path(key)
        end

        def megabytes(paths) = paths.sum { |path| File.size(path) } / (1 << 20)

        def kind(path)
          return "binary" if File.basename(File.dirname(path)) == "binaries"
          return "parse" if File.basename(File.dirname(path)) == "parse"

          File.basename(path).sub(/-[0-9a-f]{64}/, "").sub(/\A[^.]*\./, "")
        end
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
          live = Files.live
          young = Time.now - (days * 86_400)
          stale = Files.all.reject { |path| live.include?(path) || File.mtime(path) > young }
          freed = Files.megabytes(stale)
          stale.each { |path| File.delete(path) }
          puts format("swept %d file(s), %d MB; %d MB left", stale.size, freed, Files.megabytes(Files.all))
        end
      end

      class Clear < Command
        summary "Empty the runtime cache, whatever this checkout names"

        def run(_argv)
          files = Files.all
          freed = Files.megabytes(files)
          files.each { |path| File.delete(path) }
          puts format("cleared %d file(s), %d MB", files.size, freed)
        end
      end
    end
  end
end
