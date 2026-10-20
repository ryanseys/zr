# frozen_string_literal: true

require_relative "../command"

module Zr
  module CLI
    module Commands
      # `zr cache path`, `size` or `clean [--days N | --all]`.
      #
      # In `Commands`, `Cache` names this class: zr's cache is `Zr::Cache`.
      class Cache < Command
        # wasmtime's cache of compiled modules. `zr run` of a WebAssembly
        # module fills it. zr does not clean it, but `zr cache size`
        # reports it, because it can become large (67 GB on one machine).
        WASMTIME = File.expand_path("~/Library/Caches/BytecodeAlliance.wasmtime") #: String

        #: (Array[String] argv) -> void
        def run(argv)
          require_relative "../../cache/janitor"
          verb = argv.shift || "path"
          usage_error("unknown cache command '#{verb}'") unless %w[path size clean export import fetch].include?(verb)
          return export(argv) if verb == "export"
          return import(argv) if verb == "import"
          return fetch(argv) if verb == "fetch"

          options = verb == "clean" ? clean_options(argv) : {} #: { all: bool, days: Float | Integer }
          no_more!(argv)
          case verb
          when "path" then puts Paths.cache
          when "size" then size
          when "clean" then clean(**options)
          end
        end

        private

        # A usage error when `argv` holds a word that no option took.
        #: (Array[String] argv) -> void
        def no_more!(argv)
          usage_error("unexpected argument '#{argv.first}'") unless argv.empty?
        end

        # `{ all:, days: }` from the words after `clean`. It takes the
        # options out of `argv`.
        #: (Array[String] argv) -> { all: bool, days: Float | Integer }
        def clean_options(argv)
          all = !argv.delete("--all").nil?
          days = 0
          if (at = argv.index("--days"))
            usage_error("--all deletes every file; --days does not apply") if all
            _, word = argv.slice!(at, 2)
            days = Float(word.to_s, exception: false)
            usage_error("--days needs a number of days, 0 or more") unless days&.finite? && days >= 0
          end
          { all:, days: }
        end

        # What the cache holds, by kind, and its total.
        #: () -> void
        def size
          files = Zr::Cache::Janitor.all
          files.group_by { |path| Zr::Cache::Janitor.kind(path) }.sort_by { |_, group| -Zr::Cache::Janitor.bytes(group) }.each do |kind, group|
            puts format("%6d MB  %5d  %s", Zr::Cache::Janitor.megabytes(group), group.size, kind)
          end
          puts format("%6d MB  %5d  in all, in %s", Zr::Cache::Janitor.megabytes(files), files.size, Paths.cache)
          wasmtime
        end

        # The size of wasmtime's own cache, when there is one.
        #: () -> void
        def wasmtime
          return unless File.directory?(WASMTIME)

          held = Dir[File.join(WASMTIME, "**/*")].select { |path| File.file?(path) }
          puts format("%6d MB  %5d  wasmtime's own cache, in %s; zr does not clean it",
                      Zr::Cache::Janitor.megabytes(held), held.size, WASMTIME)
        end

        # Deletes the files that this zr does not use and that were not
        # used in the last `days`. With `all`, it deletes every file.
        #: (all: bool, days: Float | Integer) -> void
        def clean(all:, days:)
          sizes = Zr::Cache::Janitor.all.to_h { |path| [path, Zr::Cache::Janitor.bytes([path])] }
          gone = all ? Zr::Cache::Janitor.clear : Zr::Cache::Janitor.prune(days: days)
          freed = gone.sum { |path| sizes.fetch(path, 0) }
          puts format("deleted %d file(s), %d MB", gone.size, freed >> 20)
        end

        # `zr cache export [--target T] -o FILE`: the target's built runtime
        # as one file (lib/zr/prebuilt.rb).
        #: (Array[String] argv) -> void
        def export(argv)
          require_relative "../../prebuilt"
          out = option(argv, "-o") or usage_error("export needs -o FILE")
          target = target_of(argv)
          no_more!(argv)
          manifest = Prebuilt.export(target, out)
          bytes = manifest.fetch("files").sum { |row| row.fetch("size") }
          puts format("wrote %s: the %s runtime, %d file(s), %d MB before compression", out, target.triple, manifest.fetch("files").size,
                      bytes >> 20)
        end

        # `zr cache import FILE [--sha256 HEX]`: a runtime that `export`
        # wrote, into this cache.
        #: (Array[String] argv) -> void
        def import(argv)
          require_relative "../../prebuilt"
          sha256 = option(argv, "--sha256")
          file = argv.shift or usage_error("import needs the file of a runtime bundle")
          no_more!(argv)
          Errors.file!(file)
          manifest = Prebuilt.import(file, sha256: sha256)
          puts format("imported the %s runtime of zr %s: %d file(s)", manifest.fetch("target"), manifest.fetch("zr"), manifest.fetch("files").size)
        end

        # `zr cache fetch [--target T] [--sha256 HEX]`: the bundle of this
        # zr's release for the target, downloaded and imported.
        #: (Array[String] argv) -> void
        def fetch(argv)
          require_relative "../../prebuilt"
          sha256 = option(argv, "--sha256")
          target = target_of(argv)
          no_more!(argv)
          warn "zr: downloading #{Prebuilt.url}/#{Prebuilt.bundle_name(target)}"
          manifest = Prebuilt.fetch(target, sha256: sha256)
          puts format("imported the %s runtime of zr %s: %d file(s)", manifest.fetch("target"), manifest.fetch("zr"), manifest.fetch("files").size)
        end

        # The value after `flag` in `argv`, taken out of it, or nil.
        #: (Array[String] argv, String flag) -> String?
        def option(argv, flag)
          at = argv.index(flag) or return nil
          _, value = argv.slice!(at, 2)
          value || usage_error("#{flag} needs a value")
        end

        # The target of `--target T`, else this host's.
        #: (Array[String] argv) -> Target
        def target_of(argv)
          triple = option(argv, "--target") or return Target.default
          Target.fetch(triple) || usage_error("unknown target '#{triple}'; see zr help targets")
        end
      end
    end
  end
end
