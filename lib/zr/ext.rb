# frozen_string_literal: true

require_relative "config"
require_relative "refused"
require_relative "ext/source"

module Zr
  # The C extensions that a build links into the binary, and runs through
  # zr's C API (lib/zr/runtime/kernel/capi). They come from two places:
  # `ZR_EXT_OBJECTS` gives a bundle's path and objects directly, and
  # `ZR_NATIVE_EXT` names gems whose extension the host ruby compiled
  # when it installed them (`Ext::Source.installed`).
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
        installed = config.native_ext.flat_map { |name, version| installed(name, version) }
        (given + installed).to_h { |source| [source.bundle, source.for_mode(config.ext_mode)] }.freeze
      end
    end

    # The extensions of the installed gem `name` (the newest, or
    # `version`). Refuses a gem that is not installed, or whose install
    # kept no objects to link.
    #: (String name, String? version) -> Array[Source]
    def installed(name, version)
      specs = version ? Gem::Specification.find_all_by_name(name, version) : Gem::Specification.find_all_by_name(name)
      # RubyGems' signatures leave out a specification's directories.
      spec = specs.max_by(&:version) #: untyped
      raise Refused, "--native-ext #{name}: the gem #{name}#{" #{version}" if version} is not installed in this ruby" unless spec

      dir = spec.gem_dir #: String
      sources = Source.installed(dir)
      return sources unless sources.empty?

      raise Refused, "--native-ext #{name}: #{spec.full_name} has no compiled C extension in #{dir}/ext; " \
                     "install it with this ruby (`gem install #{name} -v #{spec.version}`), which keeps its objects there"
    end
  end
end
