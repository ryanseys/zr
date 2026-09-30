# frozen_string_literal: true

require_relative "lib/zr/dev"
require_relative "lib/zr/dev/vendor_tree"

module Zr
  module Dev
    # `zr-dev vendor`: writes vendor/ from lib/zr/vendor.rb, lib/zr/ports.rb
    # and lib/zr/version.rb. vendor/ is upstream code, byte for byte; see
    # lib/zr/vendor.rb and docs/how-to/update-vendored-code.md.
    #
    #   zr-dev vendor                 fetch, check and write vendor/, its lock and lib/zr/stdlib.rb
    #   zr-dev vendor --check         offline: each file of vendor/ matches the lock, and the
    #                                 lock matches the inputs
    #   zr-dev vendor outdated        the gems that have a newer release on rubygems.org
    #   zr-dev vendor diff GEM [V]    the files that change from the locked GEM to V (default:
    #                                 the newest), and zr's files that replace one of them
    class VendorCommand < Command
      summary "Write vendor/ (ruby's library and gems, as upstream ships them) again, or check it"
      usage "[--check] | outdated | diff GEM [VERSION]"
      host_ruby!

      def options(o) = o.on("--check", "write nothing; fail when vendor/ differs from its lock") { @check = true }

      def run(argv)
        case argv.first
        when nil then @check ? current? : write
        when "outdated" then outdated
        when "diff" then diff(*argv.drop(1))
        else fail!("no subcommand #{argv.first}; see --help")
        end
      end

      private

      def tree = VendorTree.new(fail: method(:fail!))

      def write
        Dev.pinned!(name)
        plan = tree.plan
        files = plan.files.to_h { |path, bytes| [Dev.rel(path), bytes] }
        existing = owned_files
        removed = existing - files.keys
        removed.each { |rel| File.delete(Dev.path(rel)) }
        written = files.count do |rel, bytes|
          path = Dev.path(rel)
          next false if File.file?(path) && File.binread(path) == bytes

          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(path, bytes)
          true
        end
        prune_empty_dirs
        Dev.write(VendorTree::LOCK) { |io| io.print(plan.lock_text) }
        Dev.write(VendorTree::STDLIB) { |io| io.print(plan.stdlib_text) }
        warn "vendor/: #{files.size} files, #{written} written, #{removed.size} removed"
      end

      # Offline: every owned file hashes to its line of the lock, no file
      # is missing or extra, and the inputs have not changed since.
      def current?
        _, locked, inputs = VendorTree.lock
        fail!("no #{VendorTree::LOCK}; run `zr-dev vendor`") if locked.empty?

        have = owned_files.to_h { |rel| [rel.delete_prefix("vendor/"), Digest::SHA256.file(Dev.path(rel)).hexdigest] }
        problems = []
        problems << "lib/zr/vendor.rb, lib/zr/ports.rb or lib/zr/version.rb changed since the lock" if inputs != VendorTree.inputs
        (locked.keys - have.keys).each { |rel| problems << "vendor/#{rel}: missing" }
        (have.keys - locked.keys).each { |rel| problems << "vendor/#{rel}: not in the lock" }
        (have.keys & locked.keys).each { |rel| problems << "vendor/#{rel}: differs from upstream" if have[rel] != locked[rel] }
        problems.first(20).each { |problem| warn problem }
        warn(problems.empty? ? "vendor/: #{have.size} files, current" : "vendor/: #{problems.size} problems; `zr-dev vendor` writes it again")
        problems.empty?
      end

      def outdated
        entries, = VendorTree.lock
        gems = VendorTree::GemSource.new({}, fail: method(:fail!))
        stale = entries.select { |e| %w[bundled port].include?(e.kind) }.filter_map do |e|
          latest = gems.latest(e.name)
          [e, latest] if Gem::Version.new(latest) > Gem::Version.new(e.version)
        end
        stale.each { |e, latest| puts format("%-8s %-16s %-10s -> %s", e.kind, e.name, e.version, latest) }
        puts "all #{entries.count { |e| %w[bundled port].include?(e.kind) }} gems are at their newest release" if stale.empty?
      end

      # The lib files that differ between the locked gem and `version`,
      # and each file of zr's runtime/ that has the same feature name as
      # one of them: a file to check before the update.
      def diff(gem = nil, version = nil)
        fail!("usage: zr-dev vendor diff GEM [VERSION]") unless gem
        entries, = VendorTree.lock
        locked = entries.find { |e| e.name == gem && %w[bundled port].include?(e.kind) } or fail!("#{gem} is not a gem of vendor/")
        gems = VendorTree::GemSource.new(entries.filter_map { |e| ["#{e.name}-#{e.version}.gem", e.sha256] if e.sha256 }.to_h, fail: method(:fail!))
        version ||= gems.latest(gem)
        old = lib_files(gems, gem, locked.version)
        new = lib_files(gems, gem, version)
        changed = (old.keys | new.keys).sort.reject { |rel| old[rel] == new[rel] }
        puts "#{gem} #{locked.version} -> #{version}: #{changed.size} files differ"
        changed.each do |rel|
          state = if !old.key?(rel) then "added  "
                  elsif new.key?(rel) then "changed"
                  else "removed"
                  end
          puts "  #{state}  #{rel}"
        end
        overlays = changed.filter_map { |rel| overlay(rel.delete_prefix("lib/")) }
        puts "", "zr files that replace one of them; check each before the update:", *overlays.map { |path| "  #{Dev.rel(path)}" } if overlays.any?
      end

      def lib_files(gems, gem, version)
        gems.contents(gems.fetch(gem, version)).select { |rel, _| rel.start_with?("lib/") }
      end

      # zr's file that a require of `feature` finds before vendor/.
      def overlay(feature)
        base = feature.delete_suffix(".rb")
        [Layout::EXT, *Dir[File.join(Layout::EXT, "os", "*")], Layout::RUNTIME_LIB].each do |dir|
          ["#{base}.rb", "#{base}.so.rb"].each do |name|
            path = File.join(dir, name)
            return path if File.file?(path)
          end
        end
        nil
      end

      # Each file below the directories that the tree owns, as a path
      # below ROOT, and the lock itself not among them.
      def owned_files
        VendorTree::OWNED.flat_map do |dir|
          Dir.glob("**/*", File::FNM_DOTMATCH, base: Dev.path(dir)).map { |r| "#{dir}/#{r}" }.select { |rel| File.file?(Dev.path(rel)) }
        end
      end

      def prune_empty_dirs
        VendorTree::OWNED.each do |dir|
          root = Dev.path(dir)
          next unless File.directory?(root)

          Dir.glob("**/", File::FNM_DOTMATCH, base: root).reject { |d| d.end_with?("./") }.sort_by { |d| -d.count("/") }.each do |sub|
            full = File.join(root, sub)
            Dir.rmdir(full) if Dir.empty?(full)
          end
        end
      end
    end
  end
end
