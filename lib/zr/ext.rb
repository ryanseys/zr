# frozen_string_literal: true

require_relative "config"
require_relative "refused"
require_relative "target"
require_relative "library/ports"
require_relative "ext/source"
require_relative "ext/builder"

module Zr
  # The C extensions that a build links into the binary, and runs through
  # zr's C API (lib/zr/runtime/kernel/capi). They come from two places:
  # `ZR_EXT_OBJECTS` gives a bundle's path and objects directly, and
  # `ZR_NATIVE_EXT` names gems whose extension the host ruby compiled
  # when it installed them (`Ext::Source.installed`), or that zr builds
  # (`Ext::Builder`).
  module Ext
    # The extensions of each build's Config and target triple, made once:
    # a build asks at each require that it resolves.
    BUNDLES = ObjectSpace::WeakKeyMap.new #: ObjectSpace::WeakKeyMap[Config, Hash[String, Hash[String, Source]]]

    # The bundles of each build that it did not ask for: those of a port
    # that puts its gem's C first (`wanted`).
    OPTIONAL = ObjectSpace::WeakKeyMap.new #: ObjectSpace::WeakKeyMap[Config, Hash[String, Hash[String, String]]]

    module_function

    # Each extension of the build, by the path of the bundle that a
    # require finds it at: the loader resolves a require to one
    # (`Hir::Build::Loader#extension`), and the link takes its objects.
    #: (?Config config, ?target: Target) -> Hash[String, Source]
    def bundles(config = Config.current, target: Target.default)
      (BUNDLES[config] ||= {})[target.triple] ||= begin
        optional = {} #: Hash[String, String]
        given = config.ext_objects.map { |bundle, objects| Source.given(bundle, objects) }
        installed = wanted(config, target).flat_map do |name, (version, asked)|
          sources = installed(name, version, config, target: target)
          sources.each { |source| optional[source.bundle] = name } unless asked
          sources
        rescue Refused
          # A port that puts its gem's C first stands in where that C is
          # not here: the ruby lacks the gem, or it has no C to link.
          raise if asked

          []
        end
        (OPTIONAL[config] ||= {})[target.triple] = optional.freeze
        (given + installed).to_h { |source| [source.bundle, source.for_mode(config.ext_mode)] }.freeze
      end
    end

    # The gem whose port puts its C first, when that is why the build has
    # the bundle at `path`, or nil. The program links such a bundle only
    # when a require reaches it, so a program that never requires the gem
    # carries none of its C, and a program whose gems give that gem itself
    # (a Gemfile.lock's json) uses that gem, with the port.
    #: (String path, ?Config config, ?target: Target) -> String?
    def optional_gem(path, config = Config.current, target: Target.default)
      bundles(config, target: target)
      OPTIONAL[config]&.fetch(target.triple)&.[](path)
    end

    # The gems whose own C extension the build links, each with the version
    # it asks for and whether the build asked for it: the ports that put
    # their gem's C first (`Library::Ports::Port#c_first`), in a build for
    # this host, then the gems that `--native-ext` names. `-NAME` there
    # keeps NAME's port.
    #: (Config config, Target target) -> Hash[String, [String?, bool]]
    def wanted(config, target)
      first = Library::Ports::ALL.select { |_, port| port.c_first && target.native? }.to_h { |name, port| [name, [port.version, false]] }
      asked = config.native_ext.reject { |_, version| version == false }.to_h { |name, version| [name, [version || nil, true]] }
      first.except(*config.native_ext.keys).merge(asked)
    end

    # The extensions of the build by the feature that requires each, its
    # path under its gem's lib/ (`json/ext/parser`), made once.
    FEATURES = ObjectSpace::WeakKeyMap.new #: ObjectSpace::WeakKeyMap[Config, Hash[String, Hash[String, String]]]

    # The bundle of the extension that the build links for `feature`
    # (`json/ext/parser`, `stringio.so`), or nil. It wins over a port of
    # the same C, which a library root holds: `--native-ext` asks for the
    # gem's own C.
    #: (String feature, ?Config config, ?target: Target) -> String?
    def bundle_for(feature, config = Config.current, target: Target.default)
      features(config, target: target)[feature.sub(/\.(?:so|bundle)\z/, "")]
    end

    # The features of the extensions that the build links (`json/ext/parser`).
    #: (?Config config, ?target: Target) -> Array[String]
    def linked_features(config = Config.current, target: Target.default) = features(config, target: target).keys

    #: (Config config, target: Target) -> Hash[String, String]
    def features(config, target:)
      archdir = "#{RbConfig::CONFIG["archdir"]}/"
      (FEATURES[config] ||= {})[target.triple] ||= bundles(config, target: target).each_key.to_h do |path|
        feature = path.start_with?(archdir) ? path.delete_prefix(archdir) : path[(path.rindex("/lib/").to_i + 5)..].to_s
        [feature.sub(/\.(?:so|bundle)\z/, ""), path]
      end
    end

    # Whether the build links a C extension under one of `roots`: the gem
    # whose roots they are has its C part.
    #: (Array[String] roots, ?Config config, ?target: Target) -> bool
    def linked_under?(roots, config = Config.current, target: Target.default)
      bundles(config, target: target).each_key.any? { |path| roots.any? { |root| path.start_with?("#{root}/") } }
    end

    # The extensions of the installed gem `name` (the newest, or
    # `version`), in this order: the ones that zr builds with the
    # arguments that `config` gives the gem (`ZR_EXT_CONFIG`); the
    # objects or the bundles that the host ruby's install left
    # (`Source.installed`); else the ones that zr builds from the gem's
    # extconf.rb (`Builder`). For another target than this host, zr builds
    # them for that target, as the host ruby compiled its own for the
    # host. Refuses a gem that is not installed, or a host ruby whose C
    # ABI is not the one that zr's C API has.
    #: (String name, String? version, ?Config config, ?target: Target) -> Array[Source]
    def installed(name, version, config = Config.current, target: Target.default)
      unless RbConfig::CONFIG["ruby_version"].start_with?("#{ABI}.")
        raise Refused, "--native-ext #{name}: zr's C API is ruby #{ABI}'s, and this ruby is #{RUBY_VERSION}; " \
                       "run zr with a ruby #{ABI}"
      end
      raise Refused, "--native-ext #{name}: this ruby runs without rubygems (--disable-gems), so it finds no installed gem" unless defined?(::Gem::Specification)

      specs = version ? Gem::Specification.find_all_by_name(name, version) : Gem::Specification.find_all_by_name(name)
      # RubyGems' signatures leave out a specification's directories.
      spec = specs.max_by(&:version) #: untyped
      raise Refused, "--native-ext #{name}: the gem #{name}#{" #{version}" if version} is not installed in this ruby" unless spec

      dir = spec.gem_dir #: String
      args = config.ext_config[name]
      sources = args || !target.native? ? built(spec, args || [], target) : Source.installed(dir, spec.extension_dir)
      sources = Source.archdir(spec.files, spec.extensions) if sources.empty? && !args && target.native? && spec.default_gem?
      sources = built(spec, [], target) if sources.empty?
      return sources unless sources.empty?

      raise Refused, "--native-ext #{name}: #{spec.full_name} has no C extension: no compiled one in #{dir} and no extconf.rb to build"
    end

    # The extensions of the gem `spec`, each built from its extconf.rb with
    # `args` for `target`.
    #: (untyped spec, Array[String] args, ?Target target) -> Array[Source]
    def built(spec, args, target = Target.default)
      dir = spec.gem_dir #: String
      extconfs = spec.extensions.grep(/extconf\.rb\z/) #: Array[String]
      extconfs.map { |extconf| Builder.new(File.join(dir, extconf), args: args, target: target).source(dir) }
    end
  end
end
