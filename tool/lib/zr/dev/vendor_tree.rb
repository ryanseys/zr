# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "rubygems/package"
require "stringio"
require "zlib"
require_relative "../../../../lib/zr/library/vendor"
require_relative "../../../../lib/zr/library/ports"

module Zr
  module Dev
    # vendor/, as `zr-dev vendor` writes it: each file with its bytes, the
    # sources that it came from, and the text of vendor/vendor.lock and
    # lib/zr/library/stdlib.rb. lib/zr/library/vendor.rb says what the tree
    # holds and why.
    #
    # Each source kind is a small class below: a tree at a git revision
    # (ruby's source, prism's templates), a .gem from rubygems.org, and
    # the host ruby's install (the default gems' specifications). A new
    # kind of upstream is one more class.
    class VendorTree
      # One upstream source in the lock: its kind (ruby, source, default,
      # bundled, port, license), name, version, where it came from, and
      # the SHA-256 of its .gem when it is one.
      Entry = Data.define(:kind, :name, :version, :url, :sha256) do
        def to_s = [kind, name, version, sha256 || "-", url].join(" ")
      end

      # The directories below ROOT that the tree owns: a file there that
      # the plan does not have is removed.
      OWNED = [Library::Layout::PREFIX, Library::Layout::LICENSES, Library::Layout::SOURCES, Library::Layout::TARGETS]
              .map { |dir| Dev.rel(dir) }.freeze
      LOCK = Dev.rel(Library::Layout::LOCK)
      STDLIB = "lib/zr/library/stdlib.rb"
      CACHE = "tmp/vendor/cache"

      # A native file never enters the tree: zr ports the C, or refuses.
      NATIVE = /\.(?:so|bundle|dylib|dll|o)\z/
      LICENSE = /\A(?:LICEN[CS]E|COPYING|BSDL|MIT-LICENSE|LEGAL|PSFL|license_of)/i

      # The digest of what the tree is made from, recorded in the lock, so
      # an offline check sees an edit to the inputs.
      def self.inputs
        Digest::SHA256.hexdigest([File.binread(Dev.path("lib/zr/library/vendor.rb")), Library::Ports::ALL.inspect, RUBY, RUBY_REVISION].join("\0"))
      end

      # The locked sources and files: `[entries, { rel => sha256 }, inputs]`,
      # from vendor/vendor.lock, or empty ones when there is none.
      def self.lock
        path = Dev.path(LOCK)
        return [[], {}, nil] unless File.file?(path)

        entries = []
        files = {}
        inputs = nil
        section = :sources
        File.foreach(path, chomp: true) do |line|
          next if line.start_with?("#") || line.empty?

          if line == "files"
            section = :files
          elsif line.start_with?("inputs ")
            inputs = line.split.last
          elsif section == :files
            sha, rel = line.split(" ", 2)
            files[rel] = sha
          else
            kind, name, version, sha, url = line.split(" ", 5)
            entries << Entry.new(kind, name, version, url, sha == "-" ? nil : sha)
          end
        end
        [entries, files, inputs]
      end

      attr_reader :files, :entries

      def initialize(fail:)
        @fail = fail
        @files = {}
        @entries = []
        locked = self.class.lock.first
        @gems = GemSource.new(locked.filter_map { |e| ["#{e.name}-#{e.version}.gem", e.sha256] if e.sha256 }.to_h, fail: fail)
      end

      # Collects every file and source.
      def plan
        ruby = GitTree.new(Dev.ruby_src, RUBY_REVISION, "RUBY_SRC")
        @entries << Entry.new("ruby", "ruby", RUBY, "https://github.com/ruby/ruby@#{RUBY_REVISION}", nil)
        library(ruby)
        add(Library::Layout::GEM_PRELUDE, ruby.read("gem_prelude.rb"))
        %w[COPYING BSDL LEGAL].each { |name| add(File.join(Library::Layout::LICENSES, "ruby", name), ruby.read(name)) }
        @defaults = default_gems
        rubygems_license
        @bundled = Library::Vendor::BUNDLED.to_h { |name| [name, stock_bundled(ruby).fetch(name) { @fail.call("#{name} is not in ruby's gems/bundled_gems") }] }
        @bundled.each { |name, version| gem("bundled", name, version) }
        Library::Ports::ALL.each { |name, port| gem("port", name, port.version) if port.vendored }
        stock_ports!
        minitest_license
        prism_source
        target_rubies
        @others = stock_bundled(ruby).reject { |name, _| @bundled.key?(name) }
        self
      end

      # The lock's text: the inputs' digest, each source, then each file.
      def lock_text
        head = <<~TEXT
          # vendor/vendor.lock: written by `zr-dev vendor` from lib/zr/library/vendor.rb,
          # lib/zr/library/ports.rb and lib/zr/ruby_version.rb. Do not edit.
          # `zr-dev vendor --check` checks vendor/ against it.
          #
          # A source: kind name version sha256-of-its-.gem url
          inputs #{self.class.inputs}

        TEXT
        rows = @entries.sort_by { |e| [%w[ruby source target license default bundled port].index(e.kind), e.name] }.map(&:to_s)
        sums = @files.sort.map { |path, bytes| "#{Digest::SHA256.hexdigest(bytes)} #{vendor_rel(path)}" }
        "#{head}#{rows.join("\n")}\n\nfiles\n#{sums.join("\n")}\n"
      end

      # The text of lib/zr/library/stdlib.rb: the versions that the code reads.
      def stdlib_text
        rows = ->(h) { h.map { |gem, version| "        #{gem.inspect} => #{version.inspect}" }.join(",\n") }
        <<~RUBY
          # frozen_string_literal: true

          # Generated by `zr-dev vendor` from the pinned ruby. Do not edit.

          module Zr
            module Library
              # The gems of the pinned ruby that vendor/ holds, at ruby's versions
              # (lib/zr/library/vendor.rb, lib/zr/library/roots.rb). The gems whose C zr
              # ports are in lib/zr/library/ports.rb, at zr's versions.
              module Stdlib
                # The default gems: their files are in Layout::RUBYLIBDIR.
                DEFAULT = {
          #{rows.call(@defaults)}
                }.freeze

                # The bundled gems: each one is in Layout::GEMS.
                BUNDLED = {
          #{rows.call(@bundled)}
                }.freeze

                # The other bundled gems of the pinned ruby. vendor/ does not hold
                # them at ruby's version: zr ports their C (lib/zr/library/ports.rb), or
                # refuses them. The test reference ruby has them
                # (test/support/harness/reference.rb).
                OTHER_BUNDLED = {
          #{rows.call(@others)}
                }.freeze

                # rubygems, in Layout::RUBYLIBDIR.
                RUBYGEMS = #{Gem::VERSION.inspect}
              end
            end
          end
        RUBY
      end

      # `path` below vendor/, as the lock names it.
      def vendor_rel(path) = path.delete_prefix("#{Paths::VENDOR}/")

      private

      def add(path, bytes)
        @fail.call("#{Dev.rel(path)} comes from two sources") if @files.key?(path)

        @files[path] = bytes.b
      end

      # ruby's own library, as ruby's installer lays it out: lib/X, and
      # ext/.../<ext>/lib/X under the directory of the extension's parent
      # (ext/digest/sha2/lib/sha2.rb is digest/sha2.rb).
      def library(ruby)
        ruby.files(%w[lib ext]).each do |path|
          next if path.end_with?(".gemspec") || File.basename(path) == ".document"

          rel = if path.start_with?("lib/")
                  path.delete_prefix("lib/")
                elsif (m = path.match(%r{\Aext/((?:[^/]+/)*?)[^/]+/lib/(.+)\z}))
                  m[1] + m[2]
                end
          next if rel.nil? || rel.match?(NATIVE) || left_out?(rel)

          add(File.join(Library::Layout::RUBYLIBDIR, rel), ruby.read(path))
        end
      end

      def left_out?(rel) = Library::Vendor::LEFT_OUT.each_key.any? { |entry| entry.end_with?("/") ? rel.start_with?(entry) : rel == entry }

      # The default gems of this ruby: each specification as its install
      # has it, each gem's license files from its .gem, and its executables,
      # which are the only files that ruby's install keeps in the gem's own
      # directory (Gem.bin_path finds `bundle` there).
      def default_gems
        Dir[File.join(Gem.default_specifications_dir, "*.gemspec")].sort.filter_map do |spec_path|
          spec = Gem::Specification.load(spec_path) or @fail.call("#{spec_path} does not load")
          next if Library::Vendor::LEFT_OUT_GEMS.include?(spec.name)

          add(File.join(Library::Layout::SPECIFICATIONS, "default", File.basename(spec_path)), File.binread(spec_path))
          package = @gems.fetch(spec.name, spec.version.to_s)
          @entries << Entry.new("default", spec.name, spec.version.to_s, GemSource.url(spec.name, spec.version), @gems.sha(spec.name, spec.version))
          licenses(package) { |rel, bytes| add(File.join(Library::Layout::LICENSES, spec.name, rel), bytes) }
          contents = @gems.contents(package)
          spec.executables.each do |exe|
            rel = File.join(spec.bindir, exe)
            bytes = contents[rel] or @fail.call("#{spec.full_name}: its .gem has no #{rel}")
            add(File.join(Library::Layout.gem_root(spec.name, spec.version.to_s), rel), bytes)
          end
          [spec.name, spec.version.to_s]
        end.to_h
      end

      def rubygems_license
        package = @gems.fetch("rubygems-update", Gem::VERSION)
        @entries << Entry.new("license", "rubygems-update", Gem::VERSION, GemSource.url("rubygems-update", Gem::VERSION),
                              @gems.sha("rubygems-update", Gem::VERSION))
        licenses(package) { |rel, bytes| add(File.join(Library::Layout::LICENSES, "rubygems", rel), bytes) }
      end

      # One gem in the gem home: the files of its require paths (lib) and
      # its license files, as the .gem has them, and its specification.
      def gem(kind, name, version)
        package = @gems.fetch(name, version)
        spec = package.spec
        @fail.call("#{name} #{version}: require_paths #{spec.raw_require_paths.inspect}, not [\"lib\"]") unless spec.raw_require_paths == ["lib"]

        @entries << Entry.new(kind, name, version, GemSource.url(name, version), @gems.sha(name, version))
        root = Library::Layout.gem_root(name, version)
        excluded = Library::Vendor::GEM_EXCLUDE.fetch(name, {})
        @gems.contents(package).each do |rel, bytes|
          next if excluded.key?(rel) || rel.match?(NATIVE)

          add(File.join(root, rel), bytes) if rel.start_with?("lib/") || (!rel.include?("/") && rel.match?(LICENSE))
        end
        add(File.join(Library::Layout::SPECIFICATIONS, "#{spec.full_name}.gemspec"), spec.to_ruby)
      end

      # A port that is not a gem here must be the version of ruby's own
      # copy, since that copy is its Ruby half.
      def stock_ports!
        Library::Ports::ALL.each do |name, port|
          next if port.vendored

          stock = @defaults[name]
          @fail.call("port #{name} #{port.version}: ruby's own is #{stock}. " \
                  "Make it a gem (vendored: true), or use #{stock}") if stock && stock != port.version
        end
      end

      # minitest's gem has no license file: its README carries the MIT text.
      def minitest_license
        version = @bundled.fetch("minitest")
        return if @files.keys.any? { |p| p.start_with?("#{Library::Layout.gem_root("minitest", version)}/") && File.basename(p).match?(LICENSE) }

        readme = @gems.contents(@gems.fetch("minitest", version)).fetch("README.rdoc").dup.force_encoding("UTF-8")
        text = readme[/^== LICENSE:\n(.*)\z/m, 1] or @fail.call("minitest's README has no LICENSE section")
        add(File.join(Library::Layout::LICENSES, "minitest", "LICENSE"), "The license of minitest, from its README.rdoc.\n\n#{text.strip}\n")
      end

      # prism's config.yml and templates, from its git tag: the gem has no
      # templates, and `zr-dev gen prism` renders them.
      def prism_source
        version = Library::Ports::ALL.fetch("prism").version
        tag = "v#{version}"
        @fail.call("prism #{version}: PRISM_SRC is at #{PRISM}") unless tag == PRISM
        tree = GitTree.new(Dev.prism_src, tag, "PRISM_SRC")
        @entries << Entry.new("source", "prism", version, "https://github.com/ruby/prism@#{tag}", nil)
        root = Library::Layout.source("prism", version)
        tree.files(%w[templates]).each { |path| add(File.join(root, path), tree.read(path)) }
        %w[config.yml LICENSE.md].each { |path| add(File.join(root, path), tree.read(path)) }
      end

      # The headers and rbconfig.rb of the ruby of each other target, from
      # its image, which must hold this ruby's version.
      def target_rubies
        Library::Vendor::TARGET_RUBIES.each do |triple, (image, platform)|
          prefix = "usr/local/"
          rbconfig = "#{prefix}lib/ruby/#{Library::Layout::API}/#{triple}/rbconfig.rb"
          files = ImageSource.new(image, platform, fail: @fail).files(["#{prefix}include/ruby-#{Library::Layout::API}/", rbconfig])
          text = files.fetch(rbconfig) { @fail.call("#{image}: no #{rbconfig}") }
          version = %w[MAJOR MINOR TEENY].map { |part| text[/CONFIG\["#{part}"\] = "(\d+)"/, 1] }.join(".")
          @fail.call("#{image}: ruby #{version}, not #{RUBY}") unless version == RUBY

          digest = image.split("@", 2).last
          @entries << Entry.new("target", triple, RUBY, image, digest.delete_prefix("sha256:"))
          root = Library::Layout.target_root(triple)
          files.each { |path, bytes| add(File.join(root, path.delete_prefix(prefix)), bytes) }
        end
      end

      def licenses(package)
        @gems.contents(package).each { |rel, bytes| yield rel, bytes if !rel.include?("/") && rel.match?(LICENSE) }
      end

      # ruby's list of bundled gems at RUBY_REVISION.
      def stock_bundled(ruby)
        @stock_bundled ||= ruby.read("gems/bundled_gems").lines.reject { |l| l.start_with?("#") || l.strip.empty? }
                               .to_h { |l| l.split.first(2) }
      end

      # A source tree at a git revision, or a release tree of it.
      class GitTree
        def initialize(dir, revision, variable)
          @dir = dir
          @revision = revision
          @git = File.exist?(File.join(dir, ".git"))
          raise ArgumentError, "#{variable} (#{dir}) is not a checkout or a source tree" unless File.directory?(dir)
        end

        # The files below `dirs`, as paths from the tree's root.
        def files(dirs)
          if @git
            Dev.git("ls-tree", "-r", "--name-only", @revision, *dirs, dir: @dir, err: $stderr).to_s.split("\n").sort
          else
            dirs.flat_map { |d| Dir.glob("#{d}/**/*", File::FNM_DOTMATCH, base: @dir) }.select { |r| File.file?(File.join(@dir, r)) }.sort
          end
        end

        def read(path)
          return File.binread(File.join(@dir, path)) unless @git

          batch.write("#{@revision}:#{path}\n")
          batch.flush
          header = batch.gets
          raise ArgumentError, "no #{path} at #{@revision[0, 12]} in #{@dir}" if header.nil? || header.end_with?("missing\n")

          size = header.split.last.to_i
          bytes = batch.read(size)
          batch.read(1)
          bytes
        end

        private

        def batch = @batch ||= IO.popen(["git", "-C", @dir, "cat-file", "--batch"], "r+b")
      end

      # A container image on a registry, pinned by the digest of its index:
      # the files of its layers, read in Ruby, with each layer kept in
      # tmp/vendor/cache by its SHA-256, which the download must have.
      class ImageSource
        INDEX = %w[application/vnd.oci.image.index.v1+json application/vnd.docker.distribution.manifest.list.v2+json].freeze
        MANIFEST = %w[application/vnd.oci.image.manifest.v1+json application/vnd.docker.distribution.manifest.v2+json].freeze
        REGISTRY = "https://registry-1.docker.io/v2"

        # `image` is `docker.io/<repository>@sha256:<hex>`; `platform` is
        # `[os, architecture]`.
        def initialize(image, platform, fail:)
          @repository, @digest = image.delete_prefix("docker.io/").split("@", 2)
          @platform = platform
          @fail = fail
          @fail.call("#{image}: no @sha256: digest") unless @digest&.start_with?("sha256:")
        end

        # `{ path => bytes }` of the regular files below each of `dirs`
        # (paths without the leading `/`), as the image's last layer that
        # holds each one has it.
        def files(dirs)
          out = {}
          layers.each do |layer|
            Gem::Package::TarReader.new(StringIO.new(Zlib.gunzip(blob(layer)))).each do |entry|
              path = entry.full_name.delete_prefix("./")
              next unless dirs.any? { |dir| path.start_with?(dir) }

              name = File.basename(path)
              if name.start_with?(".wh.")
                out.delete(File.join(File.dirname(path), name.delete_prefix(".wh.")))
              elsif entry.file?
                out[path] = entry.read.to_s.b
              end
            end
          end
          out
        end

        private

        # The layers of the image for the platform, from its index.
        def layers
          index = JSON.parse(get("manifests/#{@digest}", INDEX + MANIFEST))
          manifest = index
          if index["manifests"]
            os, arch = @platform
            found = index["manifests"].find { |m| m.dig("platform", "os") == os && m.dig("platform", "architecture") == arch }
            @fail.call("#{@repository}@#{@digest}: no #{os}/#{arch} image") unless found
            manifest = JSON.parse(get("manifests/#{found.fetch("digest")}", MANIFEST))
          end
          manifest.fetch("layers").map { |layer| layer.fetch("digest") }
        end

        # The bytes of the layer `digest`, which must have that SHA-256.
        def blob(digest)
          path = Dev.path("#{CACHE}/#{digest.tr(":", "-")}.tar.gz")
          unless File.file?(path)
            FileUtils.mkdir_p(File.dirname(path))
            Paths.write_atomic(path, get("blobs/#{digest}", []))
          end
          bytes = File.binread(path)
          sha = "sha256:#{Digest::SHA256.hexdigest(bytes)}"
          @fail.call("#{digest}: the download has #{sha}") unless sha == digest
          bytes
        end

        def get(rel, accept, url = "#{REGISTRY}/#{@repository}/#{rel}", limit = 5)
          @fail.call("too many redirects for #{url}") if limit.zero?

          uri = URI(url)
          request = Net::HTTP::Get.new(uri)
          # The token is only for the registry; a blob's redirect goes to a
          # store that takes none.
          request["Authorization"] = "Bearer #{token}" if url.start_with?(REGISTRY)
          request["Accept"] = accept.join(", ") unless accept.empty?
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
          case response
          when Net::HTTPSuccess then response.body.b
          when Net::HTTPRedirection then get(rel, accept, response["location"], limit - 1)
          else @fail.call("#{url}: #{response.code} #{response.message}")
          end
        end

        def token
          @token ||= begin
            uri = URI("https://auth.docker.io/token?service=registry.docker.io&scope=repository:#{@repository}:pull")
            JSON.parse(Net::HTTP.get(uri)).fetch("token")
          end
        end
      end

      # The .gem files from rubygems.org, kept in tmp/vendor/cache. A gem
      # that the lock names must have its locked SHA-256; a new one must
      # have the SHA-256 that rubygems.org publishes.
      class GemSource
        def self.url(name, version) = "https://rubygems.org/downloads/#{name}-#{version}.gem"

        def initialize(locked, fail:)
          @locked = locked
          @fail = fail
          @sums = {}
          @packages = {}
          @contents = {}
        end

        def sha(name, version) = @sums.fetch("#{name}-#{version}.gem")

        def fetch(name, version)
          file = "#{name}-#{version}.gem"
          path = Dev.path("#{CACHE}/#{file}")
          unless File.file?(path)
            FileUtils.mkdir_p(File.dirname(path))
            Paths.write_atomic(path, download(self.class.url(name, version)))
          end
          sha = Digest::SHA256.file(path).hexdigest
          if (want = @locked[file])
            @fail.call("#{file}: SHA-256 #{sha}, not #{want} (vendor/vendor.lock)") unless sha == want
          else
            # The v2 lookup of one version can answer for another platform
            # (erb has a java build), so find the ruby one in the list.
            row = JSON.parse(download("https://rubygems.org/api/v1/versions/#{name}.json"))
                      .find { |v| v["number"] == version && v["platform"] == "ruby" }
            published = row&.fetch("sha") or @fail.call("rubygems.org has no #{file}")
            @fail.call("#{file}: SHA-256 #{sha}, but rubygems.org publishes #{published}") unless sha == published
          end
          @sums[file] = sha
          @packages[path] ||= Gem::Package.new(path)
        end

        # `{ rel => bytes }` of the files a package contains.
        def contents(package)
          @contents[package.gem.path] ||= {}.tap do |out|
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

        # The newest release of `name` on rubygems.org.
        def latest(name) = JSON.parse(download("https://rubygems.org/api/v1/versions/#{name}/latest.json")).fetch("version")

        def download(url, limit = 5)
          @fail.call("too many redirects for #{url}") if limit.zero?

          response = Net::HTTP.get_response(URI(url))
          case response
          when Net::HTTPSuccess then response.body.b
          when Net::HTTPRedirection then download(response["location"], limit - 1)
          else @fail.call("#{url}: #{response.code} #{response.message}")
          end
        end
      end
    end
  end
end
