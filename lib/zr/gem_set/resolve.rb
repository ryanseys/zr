# frozen_string_literal: true

# The host ruby runs this file in a child of zr (Zr::GemSet.resolve),
# with `--disable-gems` and zr's standard library first on the load path.
# So the rubygems and bundler here are the ones that zr ships (vendor/ruby,
# the pinned ruby's), as JRuby and TruffleRuby run their own: never the
# host's, which `gem update --system` can change, and never a bundle that
# zr runs under. zr itself never loads them: the compiled compiler has
# neither. The request comes as JSON on stdin:
#
#   { "gemfile": "/app/Gemfile" or null,
#     "flags": [["csv", "3.3.6"], ["rainbow", "/src/rainbow"]],
#     "ports": { "json": "~> 3.0.2", ... } }
#
# The answer is JSON on stdout: { "gems": [gem, ...] } in search order, or
# { "error": "..." }. Each gem is
#
#   { "name", "version", "source", "roots", "refusal" }
#
# `refusal` is nil for a gem that a build can use. A gem with a C part
# that zr does not port, or a port's gem outside the versions whose C zr
# implements, has a refusal: a build stops only when a require reaches
# one of its files, as ruby fails only when it loads one.
require "rubygems"
require "json"

module ZrGemSet
  class Error < StandardError; end

  module_function

  #: (String name, String? version, String source, Array[String] roots, bool extensions, Hash[String, String] ports) -> Hash[String, untyped]
  def gem(name, version, source, roots, extensions, ports)
    refusal = refusal(name, version, source, extensions, ports)
    # A C extension that zr does not port refuses only its C part
    # (GemSet::Entry#native); a port's gem at another version refuses all.
    native = !refusal.nil? && extensions && !ports.key?(name)
    { "name" => name, "version" => version, "source" => source, "roots" => roots, "refusal" => refusal, "native" => native }
  end

  #: (String name, String? version, String source, bool extensions, Hash[String, String] ports) -> String?
  def refusal(name, version, source, extensions, ports)
    compat = ports[name]
    if compat
      return nil if version && Gem::Requirement.new(*compat.split(", ")).satisfied_by?(Gem::Version.new(version))

      fix = if source.start_with?("--gem")
              "Give a version in that range, or remove the flag"
            else
              "Put a version in that range in the Gemfile, then run 'bundle install'"
            end
      "#{name} #{version || "(no version)"} (#{source}): zr implements the C part of #{name} #{compat} only. #{fix}."
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

  # `--gem NAME=VERSION`: that version as rubygems has it installed.
  # `--gem NAME=PATH`: a gem's directory (with a gemspec or a lib/), or
  # a directory of Ruby files.
  #: (String name, String value, Hash[String, String] ports) -> Hash[String, untyped]
  def flagged(name, value, ports)
    source = "--gem #{name}=#{value}"
    return installed(name, value, source, ports) if value.match?(/\A\d+(\.[0-9A-Za-z]+)*\z/)

    dir = File.expand_path(value)
    raise Error, "#{source}: no such directory: #{dir}" unless File.directory?(dir)

    spec = gemspecs(dir).lazy.filter_map do |file|
      Dir.chdir(dir) { Gem::Specification.load(file) }
    end.find { |candidate| candidate.name == name }
    if spec
      roots = spec.require_paths.map { |path| File.expand_path(path, dir) }
      gem(name, spec.version.to_s, source, roots, !spec.extensions.empty?, ports)
    else
      version = File.basename(dir)[/\A#{Regexp.escape(name)}-(\d[\w.]*)\z/, 1]
      lib = File.join(dir, "lib")
      gem(name, version, source, [File.directory?(lib) ? lib : dir], false, ports)
    end
  end

  # The gemspecs that can describe the gem in `dir`: first the one that
  # rubygems wrote when it installed the gem (`<home>/gems/rake-13.3.1`
  # has `<home>/specifications/rake-13.3.1.gemspec`), then the gem's own.
  # A gem's own gemspec can read `git ls-files`, which an installed copy
  # cannot answer.
  #: (String dir) -> Array[String]
  def gemspecs(dir)
    installed = File.join(File.dirname(dir, 2), "specifications", "#{File.basename(dir)}.gemspec")
    own = Dir.children(dir).grep(/\.gemspec\z/).sort.map { |file| File.join(dir, file) }
    [installed].select { |file| File.basename(File.dirname(dir)) == "gems" && File.file?(file) } + own
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

  #: (String name, String version, String source, Hash[String, String] ports) -> Hash[String, untyped]
  def installed(name, version, source, ports)
    spec = Gem::Specification.find_all_by_name(name, "= #{version}").first
    raise Error, "#{source}: #{name} #{version} is not installed. Run 'gem install #{name} -v #{version}'" unless spec

    gem(name, spec.version.to_s, source, roots(spec), !spec.extensions.empty?, ports)
  end

  # The directory that rubygems loaded from, which zr checks is its own.
  #: () -> String
  def rubygems = File.dirname($LOADED_FEATURES.find { |path| path.end_with?("/rubygems.rb") }.to_s)

  # `request` is the parsed JSON of the request.
  #: (Hash[String, untyped] request) -> Hash[String, untyped]
  def answer(request)
    ports = request.fetch("ports")
    flags = request.fetch("flags").map { |name, value| flagged(name, value, ports) } #: Array[Hash[String, untyped]]
    locked = request["gemfile"] ? locked(request["gemfile"], ports) : [] #: Array[Hash[String, untyped]]
    named = flags.to_h { |gem| [gem["name"], true] }
    { "gems" => flags + locked.reject { |gem| named[gem["name"]] }, "rubygems" => rubygems }
  rescue Error => e
    { "error" => e.message }
  end
end

if $PROGRAM_NAME == __FILE__
  $stdout.write(JSON.generate(ZrGemSet.answer(JSON.parse($stdin.read))))
end
