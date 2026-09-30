# frozen_string_literal: true

require "rubygems/remote_fetcher"
require "rubygems/resolver"
require_relative "../../../../../lib/zr/ports"
require_relative "../../../../../lib/zr/stdlib"

module Zr
  module Dev
    module Gems
      # Finds a gem and the gems that it needs, as `bundle install` would
      # pick them, but only among releases for the `ruby` platform: a
      # precompiled platform gem (nokogiri-1.19.4-arm64-darwin) holds
      # native code, and its gemspec lists no extension to refuse.
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

        def initialize(store: Store.new, corpus: nil, offline: false, remote: Remote.new)
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
          raise Failure.new("not-found", "rubygems.org has no #{request} for the ruby platform") unless spec

          @store.unpack(@remote.download(spec, @store.downloads))
        end

        # Each gem that `subject` needs and zr does not have, in the order
        # that rubygems activates them.
        def dependencies(subject)
          return [] if subject.dependencies.empty?

          sets = [Provided.new, (Local.new { |name| @corpus.find(name) } if @corpus),
                  (Local.new { |name| @store.versions(name) } if @offline), (@remote.set unless @offline)]
          resolver = Gem::Resolver.new(subject.gem_dependencies, Preferred.new(sets.compact))
          requests = Resolver.ruby_platform { resolver.resolve }
          requests.filter_map do |request|
            spec = request.spec
            next if spec.is_a?(Provided::Spec) || spec.name == subject.name
            next spec.subject if spec.is_a?(Local::Spec)

            @store.unpack(@remote.download(spec, @store.downloads))
          end
        rescue Gem::DependencyError => e
          raise Failure.new("resolve", e.message.lines.first.chomp)
        end

        # Runs the block with only the `ruby` platform installable.
        def self.ruby_platform
          saved = Gem.platforms
          Gem.platforms = [Gem::Platform::RUBY]
          yield
        ensure
          Gem.platforms = saved
        end

# A set makes new specs for each lookup, and the resolver compares
# the specs of two lookups: one name, version and source is one
# spec, as Gem::Resolver::VendorSpecification has it.
module Same
  def ==(other) = other.instance_of?(self.class) && full_name == other.full_name && source == other.source
  alias eql? ==

  def hash = [self.class, full_name].hash
end

        # The gems of zr's own library, at zr's versions.
        class Provided < Gem::Resolver::Set
          class Spec < Gem::Resolver::SpecSpecification
            include Same

            def install(_options = {}) = yield(nil)
          end

          def self.versions = Stdlib::DEFAULT.merge(Stdlib::BUNDLED, Stdlib::OTHER_BUNDLED, Ports::ALL.transform_values(&:version))

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
            include Same

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

          def find_all(request) = @sets.flat_map { |set| set.find_all(request) }.uniq { |spec| [spec.name, spec.version.to_s, spec.platform.to_s] }

          def prefetch(requests) = @sets.each { |set| set.prefetch(requests) }

          def errors = @sets.flat_map(&:errors)
        end

        # rubygems.org. A test gives a Remote of its own.
        class Remote
          def set = Gem::Resolver::BestSet.new

          # The newest release of `name` for the `ruby` platform that
          # `requirement` accepts, or nil.
          def newest(name, requirement)
            request = Gem::Resolver::DependencyRequest.new(Gem::Dependency.new(name, requirement), nil)
            Resolver.ruby_platform { set.find_all(request) }.select { |spec| spec.platform.to_s == "ruby" }.max_by(&:version)
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
