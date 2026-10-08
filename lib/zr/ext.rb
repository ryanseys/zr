# frozen_string_literal: true

require_relative "config"
require_relative "refused"
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
    # The extensions of each build's Config, made once: a build asks at
    # each require that it resolves.
    BUNDLES = ObjectSpace::WeakKeyMap.new #: ObjectSpace::WeakKeyMap[Config, Hash[String, Source]]

    module_function

    # Each extension of the build, by the path of the bundle that a
    # require finds it at: the loader resolves a require to one
    # (`Hir::Build::Loader#extension`), and the link takes its objects.
    #: (?Config config) -> Hash[String, Source]
    def bundles(config = Config.current)
      BUNDLES[config] ||= begin
        given = config.ext_objects.map { |bundle, objects| Source.given(bundle, objects) }
        installed = config.native_ext.flat_map { |name, version| installed(name, version, config) }
        (given + installed).to_h { |source| [source.bundle, source.for_mode(config.ext_mode)] }.freeze
      end
    end

    # The extensions of the build by the feature that requires each, its
    # path under its gem's lib/ (`json/ext/parser`), made once.
    FEATURES = ObjectSpace::WeakKeyMap.new #: ObjectSpace::WeakKeyMap[Config, Hash[String, String]]

    # The bundle of the extension that the build links for `feature`
    # (`json/ext/parser`, `stringio.so`), or nil. It wins over a port of
    # the same C, which a library root holds: `--native-ext` asks for the
    # gem's own C.
    #: (String feature, ?Config config) -> String?
    def bundle_for(feature, config = Config.current)
      features = FEATURES[config] ||= bundles(config).each_key.to_h do |path|
        [path[(path.rindex("/lib/").to_i + 5)..].to_s.delete_suffix(".bundle"), path]
      end
      features[feature.sub(/\.(?:so|bundle)\z/, "")]
    end

    # Whether the build links a C extension under one of `roots`: the gem
    # whose roots they are has its C part.
    #: (Array[String] roots, ?Config config) -> bool
    def linked_under?(roots, config = Config.current)
      bundles(config).each_key.any? { |path| roots.any? { |root| path.start_with?("#{root}/") } }
    end

    # The extensions of the installed gem `name` (the newest, or
    # `version`), in this order: the ones that zr builds with the
    # arguments that `config` gives the gem (`ZR_EXT_CONFIG`); the
    # objects or the bundles that the host ruby's install left
    # (`Source.installed`); else the ones that zr builds from the gem's
    # extconf.rb (`Builder`). Refuses a gem that is not installed, or a
    # host ruby whose C ABI is not the one that zr's C API has.
    #: (String name, String? version, ?Config config) -> Array[Source]
    def installed(name, version, config = Config.current)
      unless RbConfig::CONFIG["ruby_version"].start_with?("#{ABI}.")
        raise Refused, "--native-ext #{name}: zr's C API is ruby #{ABI}'s, and this ruby is #{RUBY_VERSION}; " \
                       "run zr with a ruby #{ABI}"
      end
      specs = version ? Gem::Specification.find_all_by_name(name, version) : Gem::Specification.find_all_by_name(name)
      # RubyGems' signatures leave out a specification's directories.
      spec = specs.max_by(&:version) #: untyped
      raise Refused, "--native-ext #{name}: the gem #{name}#{" #{version}" if version} is not installed in this ruby" unless spec

      dir = spec.gem_dir #: String
      args = config.ext_config[name]
      sources = args ? built(spec, args) : Source.installed(dir, spec.extension_dir)
      sources = built(spec, []) if sources.empty?
      return sources unless sources.empty?

      raise Refused, "--native-ext #{name}: #{spec.full_name} has no C extension: no compiled one in #{dir} and no extconf.rb to build"
    end

    # The extensions of the gem `spec`, each built from its extconf.rb with
    # `args`.
    #: (untyped spec, Array[String] args) -> Array[Source]
    def built(spec, args)
      dir = spec.gem_dir #: String
      extconfs = spec.extensions.grep(/extconf\.rb\z/) #: Array[String]
      extconfs.map { |extconf| Builder.new(File.join(dir, extconf), args: args).source(dir) }
    end
  end
end
