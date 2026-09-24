# frozen_string_literal: true

# The pins of Zr::Libraries found by rubygems, checked against the
# digests zr was released with, and linked into a tree:
#
#   ruby lib/zr/libraries/resolve.rb DIR           the tree and manifest under DIR
#   ruby lib/zr/libraries/resolve.rb --digests     lib/zr/library_digests.rb, written
#
# Zr::Libraries runs it in a child, since only a ruby with rubygems can
# find a gem. It is never compiled into anything.

require "rubygems"
require "digest/sha2"
require "rbconfig"
require_relative "../libraries"

module Zr
  module Libraries
    module Resolve
      DIGESTS = File.expand_path("../library_digests.rb", __dir__)
      NATIVE = /\.(?:so|bundle|dylib|dll|o)\z/

      module_function

      # Each pinned gem's files, `{ name => { rel => source } }`, in PINS'
      # order.
      def files
        Libraries::PINS.to_h do |name, version|
          specs = Gem::Specification.find_all_by_name(name, "= #{version}")
          spec = specs.find(&:default_gem?) || specs.find { |s| File.directory?(s.full_gem_path) }
          unless spec
            raise Unresolved, "#{name} #{version} is not installed; `bundle install` or " \
                              "`gem install #{name} -v #{version}` installs it"
          end

          [name, spec.default_gem? ? default_files(spec) : gem_files(spec)]
        end
      end

      # A gem's files, from its own directory.
      def gem_files(spec)
        excluded = EXCLUDE.fetch(spec.name, [])
        (DIRS[spec.name] || spec.require_paths).each_with_object({}) do |sub, out|
          base = File.join(spec.full_gem_path, sub)
          Dir.glob("**/*", base: base).sort.each do |rel|
            path = File.join(base, rel)
            next unless File.file?(path)
            next if rel.match?(NATIVE) || excluded.include?(rel)

            out[rel] = path
          end
        end
      end

      # A default gem's files, from ruby's own library, as its
      # specification lists them. ruby's library directory is never taken
      # whole: it holds files zr carries its own way, and a
      # distributor's patches.
      def default_files(spec)
        dirs = RbConfig::CONFIG.values_at("sitelibdir", "rubylibdir")
        spec.files.grep(%r{\Alib/}).sort.each_with_object({}) do |file, out|
          rel = file.delete_prefix("lib/")
          next if rel.match?(NATIVE)

          path = dirs.map { |d| File.join(d, rel) }.find { |p| File.file?(p) }
          raise Unresolved, "#{rel} of #{spec.name} #{spec.version} is not in this ruby's library" unless path

          out[rel] = path
        end
      end

      # The SHA-256 of a gem's files, by name and bytes.
      def digest(files)
        Digest::SHA256.new.tap do |d|
          files.sort.each { |rel, path| d << rel << "\0" << File.binread(path) << "\0" }
        end.hexdigest
      end

      def check(found)
        require DIGESTS
        found.each do |name, files|
          want = DIGESTS_BY_NAME.fetch(name) { raise Unresolved, "no digest for #{name}; `rake gen:libraries` writes them" }
          next if digest(files) == want

          raise Unresolved, "#{name} #{PINS[name]} is not the one zr was released with: its files under " \
                            "#{File.dirname(files.values.min_by(&:size))} differ (a patched ruby?)"
        end
      end

      # The files vendor/lib holds, which no gem ships.
      def residual = Dir.glob("**/*", base: RESIDUAL).sort.select { |rel| File.file?(File.join(RESIDUAL, rel)) }
                        .grep_v(%r{\A(?:LICENSES/|VERSIONS\z)}).to_h { |rel| [rel, File.join(RESIDUAL, rel)] }

      # `{ "lib" => { rel => source }, "power_assert/lib" => ... }`: what the
      # tree links, in its two halves.
      def layout(found)
        pure = residual
        owner = pure.keys.to_h { |rel| [rel, "vendor/lib"] }
        halves = { "lib" => pure }
        found.each do |name, files|
          if APART.include?(name)
            halves[File.join(name, "lib")] = files
            next
          end
          files.each do |rel, path|
            raise Unresolved, "#{rel} is in both #{owner[rel]} and #{name}" if owner.key?(rel)

            owner[rel] = name
            pure[rel] = path
          end
        end
        halves
      end

      # The tree's name: what it holds, never where the gems are. The
      # checkout or gem it serves goes in, since its vendor/lib is linked.
      def key
        Digest::SHA256.new.tap do |d|
          d << RESIDUAL << "\0"
          PINS.each { |name, version| d << name << "\0" << version << "\0" }
          residual.each_key { |rel| d << rel << "\0" }
        end.hexdigest[0, 16]
      end

      def link(halves, tree)
        halves.each do |half, files|
          files.each do |rel, source|
            dest = File.join(tree, half, rel)
            Paths.mkdir_p(File.dirname(dest))
            File.symlink(source, dest)
          end
        end
      end

      def linked?(halves, tree)
        halves.all? do |half, files|
          files.all? { |rel, source| File.readlink(File.join(tree, half, rel)) == source rescue false } &&
            Dir.glob("**/*", base: File.join(tree, half)).count { |rel| File.symlink?(File.join(tree, half, rel)) } == files.size
        end
      end

      # The directories whose change means rubygems may answer another
      # way, and the resolve's own files, whose change may lay the tree
      # out another way; and what each is now.
      def stamps
        dirs = [__FILE__, File.expand_path("../libraries.rb", __dir__), DIGESTS]
        dirs += Gem.path.flat_map { |d| [File.join(d, "specifications"), File.join(d, "specifications/default")] }
        dirs += Dir.glob("**/", base: RESIDUAL).map { |rel| File.join(RESIDUAL, rel).chomp("/") } << RESIDUAL
        dirs.uniq.to_h { |path| [path, Libraries.stamp_of(path)] }
      end

      def run(dir)
        found = files
        check(found)
        halves = layout(found)
        tree = File.join(dir, key)
        Paths.mkdir_p(dir)
        File.open(File.join(dir, "lock"), File::RDWR | File::CREAT, 0o644) do |lock|
          lock.flock(File::LOCK_EX)
          unless File.directory?(tree) && linked?(halves, tree)
            fresh = "#{tree}.#{Process.pid}"
            Paths.remove(fresh)
            link(halves, fresh)
            old = "#{tree}.old.#{Process.pid}"
            File.rename(tree, old) if File.exist?(tree)
            File.rename(fresh, tree)
            Paths.remove(old)
          end
          manifest = { env: GEM_ENV.map { |name| ENV[name] }, stamps: stamps, tree: tree }
          path = Libraries.manifest_path
          Paths.write_atomic(path, Marshal.dump(manifest))
        end
      end

      def write_digests
        found = files
        File.write(DIGESTS, <<~RUBY)
          # frozen_string_literal: true

          # Generated by `rake gen:libraries` from the gems Zr::Libraries::PINS
          # names. Do not edit.

          module Zr
            module Libraries
              # The SHA-256 of each pinned gem's files, by name and bytes.
              DIGESTS_BY_NAME = {
          #{found.map { |name, files| "      #{name.inspect} => #{digest(files).inspect}" }.join(",\n")}
              }.freeze
            end
          end
        RUBY
        warn "#{found.size} gem(s), #{found.sum { |_, files| files.size }} file(s)"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    ARGV.first == "--digests" ? Zr::Libraries::Resolve.write_digests : Zr::Libraries::Resolve.run(ARGV.fetch(0))
  rescue Zr::Libraries::Unresolved => e
    abort "zr: #{e.message}"
  end
end
