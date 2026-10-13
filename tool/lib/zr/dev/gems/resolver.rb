# frozen_string_literal: true

require "rubygems/remote_fetcher"
require "rubygems/resolver"
require_relative "../../../../../lib/zr/library/ports"
require_relative "../../../../../lib/zr/library/stdlib"

module Zr
  module Dev
    module Gems
      # Finds a gem and the gems that it needs, as `bundle install` would
      # pick them, but the release of each version for the `ruby` platform
      # first: a precompiled platform gem (nokogiri-1.19.4-arm64-darwin)
      # holds native code, and its gemspec lists no extension to refuse. A
      # version with no `ruby` release takes the release for this machine
      # (sorbet-static's universal-darwin).
      #
      # For a dependency, the first of these that has a matching version
      # wins, in order:
      #
      # 1. zr itself: its standard library and its ports (json 3.0.2);
      #    such a gem is not given to the build, which has it already;
      # 2. the corpus, by the gem's exact path;
      # 3. with `offline`, the gems that the store holds;
      # 4. rubygems.org, into the store.
      #
      # The gem itself comes from its path, the corpus, or the newest
      # release on rubygems.org (with `offline`, the newest in the store).
      class Resolver
        # rubygems' resolver and Gem.platforms are not for more than one
        # thread at a time.
        LOCK = Mutex.new

        attr_reader :store

        def initialize(store: FetchedGems.new, corpus: nil, offline: false, remote: Remote.new)
          @store = store
          @corpus = corpus
          @offline = offline
          @remote = remote
        end

        # The gem, and the gems that a build needs next to it.
        def resolve(request)
          LOCK.synchronize do
            subject = find(request)
            [subject, dependencies(subject)]
          rescue Failure => e
            e.subject ||= subject
            raise
          end
        end

        def find(request)
          return Corpus.read(request.path, source: "path") if request.path

          found = @corpus&.find(request.name)
          return found if found && request.requirement.satisfied_by?(Gem::Version.new(found.version))

          if @offline
            newest = @store.versions(request.name).select { |s| request.requirement.satisfied_by?(Gem::Version.new(s.version)) }
                           .max_by { |s| Gem::Version.new(s.version) }
            return newest || raise(Failure.new("not-found", "#{request} is not in the corpus or the store, and --offline stops a fetch"))
          end

          spec = @remote.newest(request.name, request.requirement)
          raise Failure.new("not-found", "rubygems.org has no #{request} for the ruby platform or this machine's") unless spec

          @store.unpack(@remote.download(spec, @store.downloads))
        end

        # Each gem that `subject` needs and zr does not have, in the order
        # that rubygems activates them.
        def dependencies(subject)
          return [] if subject.dependencies.empty?

          sets = [Provided.new, (Local.new { |name| @corpus.find(name) } if @corpus),
                  (Local.new { |name| @store.versions(name) } if @offline), (@remote.set unless @offline)]
          resolver = Gem::Resolver.new(subject.gem_dependencies, Preferred.new(sets.compact))
          requests = Resolver.platforms { Resolver.requests(resolver) }
          requests.filter_map do |request|
            spec = request.spec
            next if spec.is_a?(Provided::Spec) || spec.name == subject.name
            next spec.subject if spec.is_a?(Local::Spec)

            @store.unpack(@remote.download(spec, @store.downloads))
          end
        end

        # The requests that `resolver` (a Gem::Resolver) picks. A conflict
        # (Gem::DependencyResolutionError, or Gem::UnsatisfiableDependencyError
        # for a request that no version meets) is a Failure.
        def self.requests(resolver)
          resolver.resolve
        rescue Gem::DependencyError => e
          raise Failure.new("resolve", e.message.lines.first.chomp)
        end

        # Runs the block with the `ruby` platform and this machine's
        # installable (`preferred` picks among them).
        def self.platforms
          saved = Gem.platforms
          Gem.platforms = [Gem::Platform::RUBY, Gem::Platform.local]
          yield
        ensure
          Gem.platforms = saved
        end

        # Of `specs`, for each version, its `ruby` release when it has one,
        # else its releases for this machine (universal-darwin matches an
        # arm64-darwin machine).
        def self.preferred(specs)
          specs.group_by { |spec| [spec.name, spec.version] }.values.flat_map do |releases|
            ruby = releases.select { |spec| spec.platform.to_s == Gem::Platform::RUBY }
            ruby.empty? ? releases.select { |spec| Gem::Platform.match_spec?(spec) } : ruby
          end
        end

        # A set makes new specs for each lookup, and the resolver compares
        # the specs of two lookups: one name, version and source is one
        # spec, as Gem::Resolver::VendorSpecification has it.
        module SameSpec
          def ==(other) = other.instance_of?(self.class) && full_name == other.full_name && source == other.source
          alias eql? ==

          def hash = [self.class, full_name].hash
        end

        # The gems of zr's own library, at zr's versions.
        class Provided < Gem::Resolver::Set
          class Spec < Gem::Resolver::SpecSpecification
            include SameSpec

            def install(_options = {}) = yield(nil)
          end

          def self.versions
            Library::Stdlib::DEFAULT.merge(Library::Stdlib::BUNDLED, Library::Stdlib::OTHER_BUNDLED,
                                           Library::Ports::ALL.transform_values(&:version))
          end

          def find_all(request)
            version = Provided.versions[request.name] or return []
            spec = Gem::Specification.new do |s|
              s.name = request.name
              s.version = version
            end
            request.match?(spec) ? [Spec.new(self, spec, Gem::Source::Installed.new)] : []
          end
        end

        # The subjects that a block gives for a name: nil, one, or a list.
        class Local < Gem::Resolver::Set
          class Spec < Gem::Resolver::SpecSpecification
            include SameSpec

            attr_reader :subject

            def initialize(set, subject)
              super(set, subject.to_spec, Gem::Source::Vendor.new(subject.root))
              @subject = subject
            end

            def install(_options = {}) = yield(nil)
          end

          def initialize(&lookup)
            super()
            @lookup = lookup
          end

          def find_all(request)
            Array(@lookup.call(request.name)).map { |subject| Spec.new(self, subject) }.select { |spec| request.match?(spec.spec) }
          end
        end

        # The matches of every set, those of the first set first, and one of
        # each version and platform. rubygems' resolver tries the source that it sees
        # first before the others (Gem::Resolver#search_for), so an earlier
        # set wins, and a later set still gives the versions that another
        # gem's requirement needs (minitest 5 when zr carries minitest 6).
        class Preferred < Gem::Resolver::Set
          def initialize(sets)
            super()
            @sets = sets
          end

          def find_all(request)
            Resolver.preferred(@sets.flat_map { |set| set.find_all(request) }.uniq { |spec| [spec.name, spec.version.to_s, spec.platform.to_s] })
          end

          def prefetch(requests) = @sets.each { |set| set.prefetch(requests) }

          def errors = @sets.flat_map(&:errors)
        end

        # rubygems.org. A test gives a Remote of its own.
        class Remote
          def set = Gem::Resolver::BestSet.new

          # The newest release of `name` that `requirement` accepts, for the
          # `ruby` platform or else for this machine (Resolver.preferred),
          # or nil.
          def newest(name, requirement)
            request = Gem::Resolver::DependencyRequest.new(Gem::Dependency.new(name, requirement), nil)
            Resolver.preferred(Resolver.platforms { set.find_all(request) }).max_by(&:version)
          rescue Gem::RemoteFetcher::FetchError, SocketError, SystemCallError => e
            raise Failure.new("not-found", "rubygems.org: #{e.message.lines.first.chomp}")
          end

          # The path of the downloaded .gem.
          def download(spec, dir) = spec.download(install_dir: dir)
        end
      end
    end
  end
end
