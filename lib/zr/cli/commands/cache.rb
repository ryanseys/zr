# frozen_string_literal: true

require_relative "../command"

module Zr
  module CLI
    module Commands
      # `zr cache path`, `size` or `clean [--all]`.
      #
      # In `Commands`, `Cache` names this class: zr's cache is `Zr::Cache`.
      class Cache < Command
        def run(argv)
          require_relative "../../cache/janitor"
          verb = argv.shift || "path"
          extra = argv - (verb == "clean" ? ["--all"] : [])
          usage_error("unexpected argument '#{extra.first}'") unless extra.empty?
          case verb
          when "path" then puts Paths.cache
          when "size" then size
          when "clean" then clean(all: argv.include?("--all"))
          else usage_error("unknown cache command '#{verb}'")
          end
        end

        private

        # What the cache holds, by kind, and its total.
        def size
          files = Zr::Cache::Janitor.all
          files.group_by { |path| Zr::Cache::Janitor.kind(path) }.sort_by { |_, group| -Zr::Cache::Janitor.bytes(group) }.each do |kind, group|
            puts format("%6d MB  %5d  %s", Zr::Cache::Janitor.megabytes(group), group.size, kind)
          end
          others = Zr::Cache::Janitor.old_compilers
          old_mb = others.sum { |dir| Zr::Cache::Store.tree_bytes(dir) } >> 20
          puts format("%6d MB  %5d  compiled compilers that older zr versions kept", old_mb, others.size)
          puts format("%6d MB  %5d  in all, in %s", Zr::Cache::Janitor.megabytes(files), files.size, Paths.cache)
        end

        # Deletes the files that this zr does not use, or with `all`, every
        # file, and the compiled compilers of older zr versions.
        def clean(all:)
          sizes = Zr::Cache::Janitor.all.to_h { |path| [path, Zr::Cache::Janitor.bytes([path])] }
          gone = all ? Zr::Cache::Janitor.clear : Zr::Cache::Janitor.prune
          others = Zr::Cache::Janitor.old_compilers
          freed = gone.sum { |path| sizes.fetch(path, 0) } + others.sum { |dir| Zr::Cache::Store.tree_bytes(dir) }
          others.each { |dir| Paths.remove(dir) }
          puts format("deleted %d file(s) and %d compiled compiler(s), %d MB", gone.size, others.size, freed >> 20)
        end
      end
    end
  end
end
