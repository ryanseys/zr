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
          usage_error("unknown cache command '#{verb}'") unless %w[path size clean].include?(verb)
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
      end
    end
  end
end
