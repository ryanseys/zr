# frozen_string_literal: true

# The host ruby runs this file in a child of zr (Zr::GemSet.resolve),
# with `--disable-gems` and zr's standard library first on the load path.
# So the rubygems and bundler here are the ones that zr ships (vendor/ruby,
# the pinned ruby's), as JRuby and TruffleRuby run their own: never the
# host's, which `gem update --system` can change, and never a bundle that
# zr runs under. zr itself never loads them, so a zr that zr compiled
# (`zr-dev stage`) needs neither. The request comes as JSON on stdin:
#
#   { "gemfile": "/app/Gemfile" or null,
#     "requests": { "json": ["2.19.1"], ... },
#     "ports": { "json": "~> 3.0.2", ... } }
#
# With a Gemfile, the gems are its lock's, as `bundle exec ruby` has them.
# Without one, they are the gems installed on rubygems' path (GEM_HOME,
# GEM_PATH, ~/.gem and the default directory), as a plain `ruby` finds
# them: the newest version of each, or the newest that meets the program's
# literal `gem "name", "requirement"` (`requests`).
#
# The answer is JSON on stdout: { "gems": [gem, ...] } in search order, or
# { "error": "..." }. Each gem is
#
#   { "name", "version", "source", "roots", "refusal", "native", "requested" }
#
# `refusal` is nil for a gem that a build can use. A gem with a C part
# that zr does not port, or a port's gem outside the versions whose C zr
# implements, has a refusal: a build stops only when a require reaches
# one of its files, as ruby fails only when it loads one.

# ruby 4.1 defines Monitor in its core, and its monitor.rb, which comes
# first on this load path, expects that. An older host ruby (4.0) loads
# its own monitor, which rubygems then finds as loaded.
unless defined?(Monitor)
  require "rbconfig"
  require File.join(RbConfig::CONFIG["rubylibdir"], "monitor.rb")
  $LOAD_PATH.each do |dir|
    path = File.join(dir, "monitor.rb")
    $LOADED_FEATURES << path if File.file?(path)
  end
end
require "rubygems"
require "json"

module ZrGemSet
  class Error < StandardError; end

  module_function

  #: (String name, String? version, String source, Array[String] roots, bool extensions, Hash[String, String] ports) -> Hash[String, untyped]
  def gem(name, version, source, roots, extensions, ports)
    refusal = refusal(name, version, source, extensions, ports)
    # A C extension that zr does not port refuses only its C part
    # (GemSet::Entry#native), as does a port's gem at a version whose C
    # the port does not implement: its Ruby compiles, and its own C
    # extension links with --native-ext.
    native = !refusal.nil? && extensions
    { "name" => name, "version" => version, "source" => source, "roots" => roots, "refusal" => refusal, "native" => native }
  end

  #: (String name, String? version, String source, bool extensions, Hash[String, String] ports) -> String?
  def refusal(name, version, source, extensions, ports)
    compat = ports[name]
    if compat
      return nil if version && Gem::Requirement.new(*compat.split(", ")).satisfied_by?(Gem::Version.new(version))

      fix = if source == INSTALLED
              "Install a version in that range"
            else
              "Put a version in that range in the Gemfile, then run 'bundle install'"
            end
      "#{name} #{version || "(no version)"} (#{source}): zr implements the C part of #{name} #{compat} only. #{fix}, or link the gem's own C with --native-ext #{name}=#{version}"
    elsif extensions
      "#{name} #{version} (#{source}) has a C extension, and zr has no port of it. zr compiles only Ruby"
    end
  end

  # A lock applies as `bundle exec ruby` applies it: every locked gem of
  # every group, as installed on this host.
  #: (String gemfile, Hash[String, String] ports) -> Array[Hash[String, untyped]]
  def locked(gemfile, ports)
    require "bundler"
    Bundler.ui = Bundler::UI::Silent.new if defined?(Bundler::UI::Silent)
    lockfile = Bundler.default_lockfile
    raise Error, "#{gemfile} has no lock (#{lockfile}). Run 'bundle install'" unless File.file?(lockfile)

    specs = begin
      Bundler.definition.specs
    rescue Bundler::GemNotFound => e
      # "rack-3.1.8, json-2.18.0" as "rack 3.1.8, json 2.18.0".
      missing = e.message[/Could not find (.+?) in/, 1]&.gsub(/([\w.-]+?)-(\d[\w.]*)/, '\1 \2')
      raise Error, "#{missing || e.message.lines.first.chomp} #{missing&.include?(",") ? "are" : "is"} in #{File.basename(lockfile)} " \
                   "but not installed. Run 'bundle install'"
    rescue Bundler::BundlerError => e
      raise Error, "#{File.basename(gemfile)}: #{e.message.lines.first.chomp}"
    end
    specs.reject { |spec| spec.name == "bundler" }.map do |spec|
      gem(spec.name, spec.version.to_s, File.basename(lockfile), roots(spec), !spec.extensions.empty?, ports)
    end
  end

  # The source of a gem that rubygems has installed on its path.
  INSTALLED = "installed"

  # The gems that a plain `ruby` finds on rubygems' path: the newest
  # version of each, as `Gem::Specification.find_by_path` takes the first
  # stub, which is the newest. A default gem has no root (its files are
  # ruby's own library, which zr's copies), so it adds nothing.
  #: (Hash[String, String] ports, Hash[String, Array[String]] requests) -> Array[Hash[String, untyped]]
  def installed(ports, requests)
    Gem::Specification.stubs.group_by(&:name).filter_map do |name, stubs|
      next if name == "bundler"

      asked = requests[name]
      wanted = asked ? Gem::Requirement.new(*asked) : Gem::Requirement.default
      spec = stubs.select { |stub| wanted.satisfied_by?(stub.version) }.max_by(&:version)&.to_spec or next
      paths = roots(spec)
      next if paths.empty?

      gem(name, spec.version.to_s, INSTALLED, paths, !spec.extensions.empty?, ports).merge("requested" => !asked.nil?)
    end.sort_by { |gem| gem["name"] }
  end

  # The gem's own require paths, without the directory that rubygems
  # builds its C extension into: zr never loads a native file. A default
  # gem has none: its files are in ruby's own library, which zr's
  # standard library copies, and ruby's library as a root would hide all
  # of zr's.
  #: (Gem::Specification spec) -> Array[String]
  def roots(spec)
    return [] if spec.respond_to?(:default_gem?) && spec.default_gem?

    paths = spec.respond_to?(:raw_require_paths) ? spec.raw_require_paths : spec.require_paths
    paths.map { |path| File.expand_path(path, spec.full_gem_path) }
  end

  # The directory that rubygems loaded from, which zr checks is its own.
  #: () -> String
  def rubygems = File.dirname($LOADED_FEATURES.find { |path| path.end_with?("/rubygems.rb") }.to_s)

  # `request` is the parsed JSON of the request.
  #: (Hash[String, untyped] request) -> Hash[String, untyped]
  def answer(request)
    ports = request.fetch("ports")
    gems = request["gemfile"] ? locked(request["gemfile"], ports) : installed(ports, request.fetch("requests", {}))
    { "gems" => gems, "rubygems" => rubygems }
  rescue Error => e
    { "error" => e.message }
  end
end

if $PROGRAM_NAME == __FILE__
  $stdout.write(JSON.generate(ZrGemSet.answer(JSON.parse($stdin.read))))
end
