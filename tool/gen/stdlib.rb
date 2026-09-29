# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "rubygems/package"
require_relative "../gen"

module Zr
  module Dev
    class Gen
      # zr's standard library: the pure-Ruby files of ruby 4.0.7 as a stock
      # install has them, in `stdlib/`, laid out as a ruby install lays
      # them out. zr compiles a program's `require` from this tree and
      # never from the host's gems, so a build needs no gem but zr.
      #
      #   zr-dev gen stdlib            write stdlib/ and lib/zr/stdlib.rb again
      #   zr-dev gen stdlib --check    fail when a file differs
      #
      # The sources:
      #
      # - ruby's own library and the default gems: this ruby's `rubylibdir`
      #   (ruby 4.0.7 itself), each default gem's files as its
      #   specification lists them;
      # - the bundled gems: each `.gem` from rubygems.org at the version
      #   in CRuby's `gems/bundled_gems` at RUBY_REVISION, checked against
      #   its SHA-256 in stdlib/CHECKSUMS;
      # - the license texts: each gem's own, and ruby's.
      #
      # The gems with a C part that zr ports (lib/zr/ports.rb) are not in
      # the tree: zr has their Ruby half in vendor/ext.
      class Stdlib < Generator
        host_ruby!
        writes "lib/zr/stdlib.rb"

        ROOT_DIR = "stdlib"
        VERSION_DIR = "4.0.0"
        LIB = "#{ROOT_DIR}/lib/ruby/#{VERSION_DIR}".freeze
        GEMS = "#{ROOT_DIR}/lib/ruby/gems/#{VERSION_DIR}".freeze
        LICENSES = "#{ROOT_DIR}/LICENSES".freeze
        CHECKSUMS = "#{ROOT_DIR}/CHECKSUMS".freeze
        CACHE = "tmp/stdlib/cache"

        # The default gems whose files the tree holds. The other default
        # gems have a C part: zr ports it (lib/zr/ports.rb), or refuses
        # the library.
        DEFAULT = %w[
          bundler delegate did_you_mean english erb error_highlight fileutils find forwardable ipaddr
          net-http net-protocol open-uri open3 optparse pp prettyprint resolv securerandom shellwords
          singleton syntax_suggest tempfile time timeout tmpdir tsort un uri weakref
        ].freeze

        # The bundled gems whose files the tree holds. The others are
        # ports (bigdecimal, syslog, nkf, fiddle) or refused (rbs,
        # typeprof, debug, rdoc, repl_type_completor, win32ole).
        BUNDLED = %w[
          abbrev base64 benchmark csv drb getoptlong irb logger matrix minitest mutex_m net-ftp
          net-imap net-pop net-smtp observer ostruct power_assert prime pstore racc rake readline
          reline resolv-replace rexml rinda rss test-unit
        ].freeze

        # Files of ruby's own library that no gem ships. zr includes
        # them. A name that ends in `/` is a directory.
        RESIDUAL = %w[
          bundled_gems.rb cgi.rb cgi/ coverage.rb expect.rb forwardable/impl.rb objspace.rb objspace/
          pathname.rb random/formatter.rb ripper.rb ripper/ set/ unicode_normalize/
        ].freeze

        # rubygems has no specification: its files are `rubygems.rb` and
        # `rubygems/`, as for bundler.
        GLOBBED = %w[rubygems bundler].freeze

        # Files a gem ships that ruby never loads from it.
        EXCLUDE = { "minitest" => %w[hoe/minitest.rb] }.freeze

        # A native file never enters the tree: zr ports the C, or refuses.
        NATIVE = /\.(?:so|bundle|dylib|dll|o)\z/
        LICENSE = /\A(?:LICEN[CS]E|COPYING|BSDL|MIT-LICENSE|LEGAL|PSFL|license_of)/i

        def run(_argv)
          Dev.pinned!(name)
          files, manifest = plan
          ok = check? ? compare(files) : write_tree(files)
          Dev.write(self.class.writes, check: check?) { |io| io.print(manifest) } && ok
        end

        # `{ "stdlib/..." => bytes }` for the whole tree, and the text of
        # lib/zr/stdlib.rb.
        def plan
          files = {}
          add = lambda do |rel, bytes|
            raise "#{rel} comes from two sources" if files.key?(rel)

            files[rel] = bytes
          end
          lib = RbConfig::CONFIG["rubylibdir"]

          RESIDUAL.each do |entry|
            names = entry.end_with?("/") ? Dir.glob("#{entry}**/*", base: lib).select { |r| File.file?(File.join(lib, r)) } : [entry]
            fail!("#{entry} is not in #{lib}") if names.empty?
            names.sort.each { |rel| add.("#{LIB}/#{rel}", File.binread(File.join(lib, rel))) }
          end

          defaults = DEFAULT.to_h do |gem|
            spec = default_spec(gem)
            rels = if GLOBBED.include?(gem)
                     ["#{gem}.rb", *Dir.glob("#{gem}/**/*", base: lib)]
                   else
                     spec.files.grep(%r{\Alib/}).map { |f| f.delete_prefix("lib/") }
                   end
            rels.sort.each do |rel|
              path = File.join(lib, rel)
              next if rel.match?(NATIVE) || !File.file?(path)

              add.("#{LIB}/#{rel}", File.binread(path))
            end
            add.("#{GEMS}/specifications/default/#{spec.full_name}.gemspec", File.binread(spec.loaded_from))
            licenses(gem, spec.version.to_s) { |rel, bytes| add.("#{LICENSES}/#{gem}/#{rel}", bytes) }
            [gem, spec.version.to_s]
          end
          ["rubygems.rb", *Dir.glob("rubygems/**/*", base: lib)].sort.each do |rel|
            path = File.join(lib, rel)
            add.("#{LIB}/#{rel}", File.binread(path)) if File.file?(path) && !rel.match?(NATIVE)
          end
          licenses("rubygems-update", Gem::VERSION) { |rel, bytes| add.("#{LICENSES}/rubygems/#{rel}", bytes) }
          %w[COPYING BSDL].each { |name| add.("#{LICENSES}/ruby/#{name}", Dev.cruby(name).b) }

          sums = checksums
          bundled = BUNDLED.to_h do |gem|
            version = stock_bundled.fetch(gem) { fail!("#{gem} is not in ruby's gems/bundled_gems") }
            package = fetch(gem, version, sums)
            spec = package.spec
            fail!("#{gem} #{version}: require_paths #{spec.raw_require_paths.inspect}, not [\"lib\"]") unless spec.raw_require_paths == ["lib"]

            dir = "#{GEMS}/gems/#{spec.full_name}"
            excluded = EXCLUDE.fetch(gem, [])
            contents(package).each do |rel, bytes|
              if rel.start_with?("lib/")
                sub = rel.delete_prefix("lib/")
                add.("#{dir}/#{rel}", bytes) unless sub.match?(NATIVE) || excluded.include?(sub)
              elsif !rel.include?("/") && rel.match?(LICENSE)
                add.("#{dir}/#{rel}", bytes)
              end
            end
            add.("#{GEMS}/specifications/#{spec.full_name}.gemspec", spec.to_ruby.b)
            [gem, version]
          end
          # minitest's gem has no license file: its README carries the MIT
          # text.
          minitest = "#{GEMS}/gems/minitest-#{bundled.fetch("minitest")}"
          if files.keys.none? { |rel| rel.start_with?("#{minitest}/") && File.basename(rel).match?(LICENSE) }
            readme = contents(fetch("minitest", bundled.fetch("minitest"), sums)).fetch("README.rdoc").force_encoding("UTF-8")
            text = readme[/^== LICENSE:\n(.*)\z/m, 1] or fail!("minitest's README has no LICENSE section")
            add.("#{minitest}/LICENSE", "The license of minitest, from its README.rdoc.\n\n#{text.strip}\n".b)
          end
          add.(CHECKSUMS, sums.sort.map { |file, sha| "#{sha}  #{file}\n" }.join.b)

          others = stock_bundled.reject { |gem, _| bundled.key?(gem) }
          [files, manifest(defaults, bundled, others)]
        end

        def default_spec(gem)
          version = default_versions.fetch(gem) { fail!("#{gem} is not a default gem of this ruby") }
          spec = Gem::Specification.load(File.join(Gem.default_specifications_dir, "#{gem}-#{version}.gemspec"))
          spec or fail!("no default specification for #{gem}")
        end

        def default_versions
          @default_versions ||= Dir[File.join(Gem.default_specifications_dir, "*.gemspec")].to_h do |path|
            base = File.basename(path, ".gemspec")
            base.match(/\A(.+)-([^-]+)\z/).captures
          end
        end

        # CRuby's list of bundled gems at RUBY_REVISION.
        def stock_bundled
          @stock_bundled ||= Dev.cruby("gems/bundled_gems").lines.reject { |l| l.start_with?("#") || l.strip.empty? }
                                .to_h { |l| l.split.first(2) }
        end

        # The license files of `gem` at `version`, from its .gem. Yields
        # each file's name and bytes.
        def licenses(gem, version)
          contents(fetch(gem, version, checksums)).each do |rel, bytes|
            yield rel, bytes if !rel.include?("/") && rel.match?(LICENSE)
          end
        end

        # `{ "name-version.gem" => sha256 }` from stdlib/CHECKSUMS.
        def checksums
          @checksums ||= begin
            path = Dev.path(CHECKSUMS)
            File.file?(path) ? File.readlines(path, chomp: true).to_h { |l| l.split("  ", 2).reverse } : {}
          end
        end

        # The package of `gem` at `version`: from tmp/stdlib/cache, else
        # rubygems.org. A known checksum must match; a new one is kept.
        def fetch(gem, version, sums)
          file = "#{gem}-#{version}.gem"
          path = Dev.path("#{CACHE}/#{file}")
          unless File.file?(path)
            FileUtils.mkdir_p(File.dirname(path))
            Paths.write_atomic(path, download("https://rubygems.org/downloads/#{file}"))
          end
          sha = Digest::SHA256.file(path).hexdigest
          if (want = sums[file])
            fail!("#{file}: SHA-256 #{sha}, not #{want} (stdlib/CHECKSUMS)") unless sha == want
          else
            # The v2 lookup of one version can answer for another platform
            # (erb has a java build), so find the ruby one in the list.
            row = JSON.parse(download("https://rubygems.org/api/v1/versions/#{gem}.json"))
                      .find { |v| v["number"] == version && v["platform"] == "ruby" }
            published = row&.fetch("sha") or fail!("rubygems.org has no #{file}")
            fail!("#{file}: SHA-256 #{sha}, but rubygems.org publishes #{published}") unless sha == published
            sums[file] = sha
          end
          (@packages ||= {})[path] ||= Gem::Package.new(path)
        end

        # `{ rel => bytes }` of the files a package contains.
        def contents(package)
          (@contents ||= {})[package.gem.path] ||= {}.tap do |out|
            package.gem.with_read_io do |io|
              Gem::Package::TarReader.new(io).each do |entry|
                next unless entry.full_name == "data.tar.gz"

                Zlib::GzipReader.wrap(entry) do |gz|
                  Gem::Package::TarReader.new(gz).each { |file| out[file.full_name] = file.read.b if file.file? }
                end
              end
            end
          end
        end

        def download(url, limit = 5)
          fail!("too many redirects for #{url}") if limit.zero?

          response = Net::HTTP.get_response(URI(url))
          case response
          when Net::HTTPSuccess then response.body.b
          when Net::HTTPRedirection then download(response["location"], limit - 1)
          else fail!("#{url}: #{response.code} #{response.message}")
          end
        end

        def manifest(defaults, bundled, others)
          rows = ->(h) { h.map { |gem, version| "      #{gem.inspect} => #{version.inspect}" }.join(",\n") }
          <<~RUBY
            # frozen_string_literal: true

            # Generated by `zr-dev gen stdlib` from ruby #{RUBY}. Do not edit.

            module Zr
              # The gems of zr's standard library (stdlib/), at the versions that
              # ruby #{RUBY} ships (lib/zr/libraries.rb).
              module Stdlib
                # The default gems: their files are in stdlib/lib/ruby/#{VERSION_DIR}.
                DEFAULT = {
            #{rows.(defaults)}
                }.freeze

                # The bundled gems: each one is in stdlib/lib/ruby/gems/#{VERSION_DIR}/gems.
                BUNDLED = {
            #{rows.(bundled)}
                }.freeze

                # The other bundled gems of ruby #{RUBY}. zr does not carry them:
                # it ports their C (lib/zr/ports.rb), or refuses them. The test
                # reference ruby has them (test/support/harness/reference.rb).
                OTHER_BUNDLED = {
            #{rows.(others)}
                }.freeze

                # rubygems, in stdlib/lib/ruby/#{VERSION_DIR}.
                RUBYGEMS = #{Gem::VERSION.inspect}
              end
            end
          RUBY
        end

        # Removes the files of stdlib/ that the plan does not have, and
        # writes each file that differs.
        # The files that stdlib/ holds now, below the root.
        def existing_files
          root = Dev.path(ROOT_DIR)
          return [] unless File.directory?(root)

          Dir.glob("**/*", File::FNM_DOTMATCH, base: root).map { |r| "#{ROOT_DIR}/#{r}" }.select { |r| File.file?(Dev.path(r)) }
        end

        def write_tree(files)
          root = Dev.path(ROOT_DIR)
          existing = existing_files
          (existing - files.keys).each { |rel| File.delete(Dev.path(rel)) }
          changed = files.count do |rel, bytes|
            path = Dev.path(rel)
            next false if File.file?(path) && File.binread(path) == bytes

            FileUtils.mkdir_p(File.dirname(path))
            File.binwrite(path, bytes)
            true
          end
          Dir.glob("**/", base: root).sort_by { |d| -d.count("/") }.each do |dir|
            full = File.join(root, dir)
            Dir.rmdir(full) if Dir.empty?(full)
          end
          warn "stdlib/: #{files.size} files, #{changed} written, #{(existing - files.keys).size} removed"
          true
        end

        def compare(files)
          existing = existing_files
          extra = existing - files.keys
          differ = files.reject { |rel, bytes| File.file?(Dev.path(rel)) && File.binread(Dev.path(rel)) == bytes }.keys
          (extra.first(10) + differ.first(10)).each { |rel| warn "#{rel}: out of date" }
          ok = extra.empty? && differ.empty?
          warn(ok ? "stdlib/: current" : "stdlib/: #{differ.size} differ, #{extra.size} extra; `zr-dev gen stdlib` writes it")
          ok
        end
      end
    end
  end
end
