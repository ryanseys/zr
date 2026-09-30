# frozen_string_literal: true

module Zr
  module Dev
    module Gems
      # One gem on disk: its name and version, the directory that holds
      # it, its require paths below that directory, its C extensions, its
      # runtime dependencies as `[name, requirement]`, and where it came
      # from (`rubygems`, `corpus` or `path`).
      Subject = Data.define(:name, :version, :root, :require_paths, :extensions, :dependencies, :source) do
        # The subject of an unpacked gem's specification. `raw_require_paths`
        # does not add the directory that rubygems builds a C extension
        # into.
        def self.from_spec(spec, root, source)
          new(name: spec.name, version: spec.version.to_s, root: root, require_paths: spec.raw_require_paths,
              extensions: spec.extensions, source: source,
              dependencies: spec.runtime_dependencies.map { |dep| [dep.name, dep.requirement.to_s] })
        end

        # The require roots, as absolute paths.
        def roots = require_paths.map { |path| File.expand_path(path, root) }

        def cext? = !extensions.empty?

        def full_name = "#{name}-#{version}"

        def to_s = "#{name} #{version}"

        # The dependencies, as the resolver takes them.
        def gem_dependencies = dependencies.map { |name, requirement| Gem::Dependency.new(name, requirement.split(", ")) }

        # A specification with only what the resolver reads.
        def to_spec
          subject = self
          Gem::Specification.new do |spec|
            spec.name = subject.name
            spec.version = subject.version
            subject.dependencies.each { |name, requirement| spec.add_runtime_dependency(name, *requirement.split(", ")) }
          end
        end
      end
    end
  end
end
