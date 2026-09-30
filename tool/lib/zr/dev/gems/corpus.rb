# frozen_string_literal: true

require "json"

module Zr
  module Dev
    module Gems
      # A directory of unpacked gems, one directory for each name, as
      # zeo's corpus has them (`<corpus>/rake`). A corpus can hold very
      # many gems, so the tool finds a gem by its exact path and never
      # lists the corpus.
      class Corpus
        # zeo's markers: the version, and the metadata of the release.
        VERSION = ".zeo-probe-version"
        SPEC = ".zeo-probe-spec"

        # Gem::Specification.load evaluates a gemspec in the process, and
        # a gemspec reads files relative to its directory. One thread
        # changes the directory at a time.
        LOAD = Mutex.new

        attr_reader :dir

        def initialize(dir)
          @dir = File.expand_path(dir)
        end

        # The gem `name`, or nil.
        def find(name)
          path = File.join(@dir, name)
          File.directory?(path) ? Corpus.read(path, source: "corpus", name: name) : nil
        end

        # The subject of the unpacked gem in `dir`. It reads the store's
        # marker, zeo's markers, the gem's gemspec and the name of the
        # directory (`rake-13.4.2`), in that order. Only a gemspec gives
        # the dependencies. Raises a Failure when nothing gives a version.
        def self.read(dir, source:, name: nil)
          raise Failure.new("not-found", "no directory #{dir}") unless File.directory?(dir)

          stored = FetchedGems.new.read(dir)
          return stored.with(source: source) if stored

          base_name, base_version = File.basename(dir).match(/\A(.+?)-(\d[^-]*)\z/)&.captures
          spec = gemspec(dir, name || base_name)
          name ||= spec&.name || base_name || File.basename(dir)
          zeo = marker(dir)
          version = zeo[:version] || spec&.version&.to_s || base_version
          raise Failure.new("not-found", "#{dir}: no #{VERSION}, gemspec or <name>-<version> name gives the version") unless version

          Subject.new(name: name, version: version, root: dir, source: source,
                      require_paths: zeo[:require_paths] || spec&.raw_require_paths || default_paths(dir),
                      extensions: zeo[:extensions] || spec&.extensions || [],
                      dependencies: spec ? spec.runtime_dependencies.map { |dep| [dep.name, dep.requirement.to_s] } : [])
        end

        # zeo's markers, as `{ version:, require_paths:, extensions: }`
        # with nil for each one that is missing.
        def self.marker(dir)
          version = File.join(dir, VERSION)
          spec = File.join(dir, SPEC)
          fields = File.file?(spec) ? JSON.parse(File.read(spec)) : {}
          { version: File.file?(version) ? File.read(version).strip : nil,
            require_paths: fields["require_paths"], extensions: fields["extensions"] }
        end

        # `<name>.gemspec`, or the only gemspec when the name is not known.
        # A gem's directory is small, so this lists it.
        def self.gemspec(dir, name)
          files = Dir.children(dir).grep(/\.gemspec\z/)
          file = name ? files.find { |f| f == "#{name}.gemspec" } : (files.first if files.one?)
          return nil unless file

          LOAD.synchronize { Dir.chdir(dir) { Gem::Specification.load(File.join(dir, file)) } }
        end

        def self.default_paths(dir) = File.directory?(File.join(dir, "lib")) ? ["lib"] : ["."]
      end
    end
  end
end
