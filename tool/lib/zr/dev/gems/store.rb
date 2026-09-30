# frozen_string_literal: true

require "fileutils"
require "json"
require "rubygems/package"

module Zr
  module Dev
    module Gems
      # The gems that the tool fetched, as a gem home that rubygems installs:
      #
      #   cache/<name>-<version>.gem                the download; never fetched again
      #   gems/<name>-<version>/                    the unpacked files
      #   specifications/<name>-<version>.gemspec
      #
      # So ruby reads it with GEM_PATH, and `zr build --gem NAME=DIR` reads
      # the specification next to the gem's directory, as it does for any
      # installed gem.
      #
      # The unpack is Gem::Package's, in Ruby: no `gem install`, so no C
      # compiles and no code of the gem runs. Each gem directory also gets
      # `.zr-gems.json`, what the tool reads back (no gemspec to evaluate).
      class Store
        MARKER = ".zr-gems.json"

        attr_reader :dir

        def initialize(dir = TMP)
          @dir = dir
        end

        def gems = File.join(@dir, "gems")

        def specifications = File.join(@dir, "specifications")

        # The install directory that rubygems downloads into (its `cache/`).
        def downloads = @dir

        # Whether `subject` is a gem of this store.
        def holds?(subject) = File.dirname(subject.root) == gems

        # The unpacked `name` at `version`, or nil.
        def find(name, version) = read(File.join(gems, "#{name}-#{version}"))

        # Each unpacked version of `name`. The store holds only what the
        # tool fetched, so a listing of it is small.
        def versions(name)
          return [] unless File.directory?(gems)

          pattern = /\A#{Regexp.escape(name)}-\d[^-]*\z/
          Dir.children(gems).grep(pattern).filter_map { |base| read(File.join(gems, base)) }.select { |subject| subject.name == name }
        end

        # Unpacks the .gem at `path`, unless the store has it, and returns
        # its subject. A package that does not verify raises
        # Gem::Package::FormatError or Gem::Security::Exception.
        def unpack(path)
          package = Gem::Package.new(path)
          spec = package.spec
          dest = File.join(gems, spec.full_name)
          return read(dest) if File.file?(File.join(dest, MARKER))

          work = "#{dest}.#{Process.pid}.#{Thread.current.object_id}"
          FileUtils.rm_rf(work)
          FileUtils.mkdir_p([work, specifications])
          package.extract_files(work)
          File.write(File.join(specifications, "#{spec.full_name}.gemspec"), spec.to_ruby)
          subject = Subject.from_spec(spec, dest, "rubygems")
          File.write(File.join(work, MARKER), JSON.pretty_generate(subject.to_h.except(:root, :source)))
          FileUtils.rm_rf(dest)
          File.rename(work, dest)
          read(dest)
        ensure
          FileUtils.rm_rf(work) if work && File.exist?(work)
        end

        # Moves the store of an older zr-dev (`src/`, with a gemspec in each
        # gem's directory, and `rubygems/cache/`) to this layout.
        def migrate
          old = File.join(@dir, "src")
          return unless File.directory?(old) && !File.exist?(gems)

          File.rename(old, gems)
          FileUtils.mkdir_p(specifications)
          Dir.children(gems).each do |base|
            subject = read(File.join(gems, base))
            spec = subject && File.join(gems, base, "#{subject.name}.gemspec")
            File.rename(spec, File.join(specifications, "#{base}.gemspec")) if spec && File.file?(spec)
          end
          cache = File.join(@dir, "rubygems", "cache")
          File.rename(cache, File.join(@dir, "cache")) if File.directory?(cache) && !File.exist?(File.join(@dir, "cache"))
        end

        def read(dir)
          marker = File.join(dir, MARKER)
          return nil unless File.file?(marker)

          fields = JSON.parse(File.read(marker), symbolize_names: true)
          Subject.new(**fields, root: dir, source: "rubygems")
        end
      end
    end
  end
end
