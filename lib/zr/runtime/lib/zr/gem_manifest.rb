# frozen_string_literal: true

# The gems of this program, given to rubygems. A zr program carries the
# files of each gem it uses: its build compiled them in, and wrote the
# name, version and source of each gem in the program's gem manifest
# (lib/zr/manifest.rb).
#
# - Gem::Specification lists the gems of the ruby install that runs the
#   program, as rubygems finds them: its default and bundled gems. Each
#   gem of the program's Gemfile.lock or of the build's gem path stands
#   in place of the install's gem of that name, and a gem of the build
#   that the install lacks is listed too. A program that no zr ran has no install, and
#   lists only its own gems.
# - The gems of the program's Gemfile.lock are active from the start, as
#   bundler's setup activates a bundle. Any other gem is
#   active from the first require (or autoload) that loads one of its
#   files, as rubygems' Kernel#require activates it: the kernel asks
#   `Kernel.activating` before such a file runs, and rubygems' own
#   Specification#activate answers. A require_relative or a load
#   activates nothing, as in ruby. The gems of the files loaded before
#   rubygems are active in the order of those requires.
# - `gem` accepts one of the program's own gems at a version that its
#   requirements match, and raises Gem::LoadError for another version.
#   Its message is bundler's, and its answer is rubygems' (false: already
#   active). For any other gem, `gem` is rubygems' own.
#
# This holds while rubygems searches the gem directories that the program
# started with. A program that points rubygems at others (Gem.use_paths,
# Gem.paths=, or GEM_HOME and GEM_PATH with Gem.clear_paths, as
# rubygems' own tests do) gets rubygems' own answers from them, as in
# ruby: the gems there, `gem` and `require` that activate them, and
# Gem.finish_resolve. Each of these asks when it runs, because
# Gem.paths= resets the specifications before it sets the new paths.
#
# The prelude requires this file after rubygems, and Kernel#gem's first
# call (lib/zr/runtime/core/kernel.rb) does the same.
# A gem with no version (null) counts as version 0.
rows = Primitive.zr_load_names(9).scan(/\{"name":"([^"]+)","version":(?:"([^"]+)"|null),"source":"([^"]*)"(?:,"dir":"((?:[^"\\]|\\.)*)")?/)
# The rows of ruby's install (`default` and `bundled`) come first, so a
# gem that the program carries takes the place of its install row.
defaults = rows.filter_map { |name, _version, source| name if source == "default" }
unversioned = rows.filter_map { |name, version| name unless version }
specs = rows.to_h do |name, version, _source, dir|
  spec = Gem::Specification.new do |s|
    s.name = name
    s.version = version || "0"
  end
  if dir
    # Where the build found the gem, as an installed gem's directory
    # (lib/zr/manifest.rb). The JSON escapes only `"` and `\` in a path.
    dir = dir.gsub(/\\(.)/, '\1')
    spec.instance_variable_set(:@full_gem_path, dir)
    spec.instance_variable_set(:@gem_dir, dir)
  else
    # A gem of ruby's install has its gemspec there, as rubygems reads
    # it: a default gem's in the directory of default specifications.
    dir = defaults.include?(name) ? Gem.default_specifications_dir : File.join(Gem.default_dir, "specifications")
    spec.loaded_from = File.join(dir, "#{name}-#{spec.version}.gemspec")
  end
  [name, spec]
end
# The gems of the program's own bundle: not ruby's library (`stdlib`),
# not zr's ports (`port`), not the install's list, and not a gem from
# rubygems' path (`installed`), which activates at its first require.
own = specs.slice(*rows.filter_map { |name, _version, source| name unless %w[stdlib port default bundled installed].include?(source) })

home = Gem.dir
path = Gem.path
booted = -> { Gem.dir == home && Gem.path == path }

rubygems_record = Gem::Specification.method(:specification_record)
own_record = lambda do
  installed = rubygems_record.call.stubs
  names = installed.to_h { |stub| [stub.name, true] }
  stubs = installed.reject { |stub| own.key?(stub.name) } + specs.values.select { |spec| own.key?(spec.name) || !names.key?(spec.name) }
  # `all` loads each full spec from its stub when something asks, as rubygems' own record does.
  Gem::SpecificationRecord.new(Gem::SpecificationRecord.dirs_with_abi(Gem::Specification.dirs)).tap do |made|
    made.all = stubs
    made.instance_variable_set(:@all, nil)
  end
end
record = nil
Gem.post_reset { record = nil }
Gem::Specification.singleton_class.send(:define_method, :specification_record) do
  booted.call ? (record ||= own_record.call) : rubygems_record.call
end

rubygems_finish_resolve = Gem.method(:finish_resolve)
Gem.singleton_class.send(:define_method, :finish_resolve) { |*args| booted.call ? [] : rubygems_finish_resolve.call(*args) }
# rubygems' own ivar: an `@name` in zr's runtime files is a hidden one.
Gem.singleton_class.send(:define_method, :discover_gems_on_require) do
  booted.call ? false : instance_variable_get(:@discover_gems_on_require)
end

# A gem whose C zr ports has its extension built in, so rubygems does
# not skip the install's copy of it for an extension directory that
# zr never builds (Gem::BasicSpecification#ignored?).
ported = Primitive.zr_load_names(9)[/"ports":\[([^\]]*)\]/, 1].to_s.scan(/"([^"]+)"/).flatten
Gem::BasicSpecification.prepend(Module.new do
  define_method(:ignored?) { ported.include?(name) ? false : super() }
end)

# The gem of each file that the program carries (lib/zr/manifest.rb's
# `owners`), by the path that the program sees.
carried = {}
Primitive.zr_load_names(9).scan(/\{"name":"([^"]+)","files":\[([^\]]*)\]\}/) do |name, list|
  list.scan(/"((?:[^"\\]|\\.)*)"/) { |(file)| carried[file.gsub(/\\(.)/, '\1')] = name }
end

# The name of the gem of the file at `file`: a carried file's, else a
# default gem's by rubygems' own table of their files
# (Gem.register_default_spec), which names each file by its path below
# a require path. nil for any other file.
named = lambda do |file|
  carried.fetch(file) do
    parts = file.delete_suffix(File.extname(file)).split("/")
    (1...parts.size).lazy.filter_map { |at| Gem.find_default_spec(parts.drop(at).join("/"))&.name }.first
  end
end

# A require that finds its file activates only that file's gem, as
# rubygems' own require does: the gem that `named` gives, at the version
# that the program carries. rubygems' search of every gem is for a file
# that no directory has, which a require of the program raises
# LoadError for. rubygems' own files load while it reads its list of
# gems (its autoloads), and activate nothing.
finding = false
activate = lambda do |file|
  next if finding || !booted.call

  name = named.call(file)
  next if name.nil? || Gem.loaded_specs.key?(name)

  begin
    finding = true
    version = specs[name]&.version
    found = Gem::Specification.stubs_for(name).find { |stub| version.nil? || stub.version == version }
    found&.to_spec&.activate
  ensure
    finding = false
  end
end

# The bundle is active before the first line. rubygems' own boot
# activated the default gems of the files loaded before it
# (`spec.activate if already_loaded?(file)`), in its own order; the gems
# go in again in the order of their first files, as ruby, whose
# rubygems is there from the start, activates them. The program's own
# row of each gem stands in for the install's, whose list rubygems
# reads only when something asks.
early = Gem.loaded_specs.dup
Gem.loaded_specs.clear
own.each_value do |spec|
  spec.activated = true
  Gem.loaded_specs[spec.name] = spec
end
$LOADED_FEATURES.dup.each do |file|
  name = named.call(file)
  next if name.nil? || Gem.loaded_specs.key?(name)

  if (spec = early.delete(name))
    Gem.loaded_specs[name] = spec
  else
    specs[name]&.activate
  end
end
early.each { |name, spec| Gem.loaded_specs[name] ||= spec }
Primitive.zr_hidden_set(Kernel, :__activate__, activate)
# rubygems' own Kernel#require, which a require that the build resolved
# stands in for (Kernel.plain_require?).
Primitive.zr_hidden_set(Kernel, :__require__, Kernel.instance_method(:require))

rubygems_gem = Kernel.instance_method(:gem)
Kernel.send(:define_method, :gem) do |dep, *requirements|
  name = dep.respond_to?(:name) ? dep.name : dep.to_s
  next rubygems_gem.bind_call(self, dep, *requirements) unless booted.call && own.key?(name)

  requirements.pop if requirements.last.is_a?(Hash)
  dep = Gem::Dependency.new(dep, requirements) unless dep.respond_to?(:name) && dep.respond_to?(:requirement)
  spec = own[dep.name]
  unless spec && dep.matches_spec?(spec)
    message = if unversioned.include?(dep.name)
                "zr built this program with #{dep.name} from a directory that has no gemspec, so its version " \
                  "is unknown and does not match #{dep.requirement}."
              else
                "can't activate #{dep}, already activated #{spec.full_name}. " \
                  "Make sure all dependencies are added to Gemfile."
              end
    error = Gem::LoadError.new(message)
    error.name = dep.name
    error.requirement = dep.requirement
    raise error
  end
  # A gem of the bundle is active from the start, so rubygems' own `gem`
  # answers false for it, as ruby's does after a require of the gem.
  false
end
Kernel.send(:private, :gem)
