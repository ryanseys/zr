# frozen_string_literal: true

# The gems of this program, given to rubygems as bundler's setup gives it
# a bundle (Bundler::RubygemsIntegration#replace_entrypoints and
# Bundler::Runtime#setup). A zr program has no gem directory to search:
# its build compiled in the files of each gem, and wrote the name and
# version of each in the program's gem manifest (lib/zr/manifest.rb).
#
# So, as under `bundle exec`:
# - Gem::Specification lists only those gems, and Gem.loaded_specs has
#   each of them;
# - `gem` accepts one of them at a version that its requirements match,
#   and raises Gem::LoadError for any other gem or version. Its message
#   is bundler's, and its answer is rubygems' (false: already active).
#
# The prelude requires this file after rubygems, and Kernel#gem's first
# call (lib/zr/runtime/core/kernel.rb) does the same.
# A `--gem` directory with no gemspec has no version (null), and here
# counts as version 0.
rows = Primitive.zr_load_names(9).scan(/\{"name":"([^"]+)","version":(?:"([^"]+)"|null),"source":"[^"]*"(?:,"dir":"((?:[^"\\]|\\.)*)")?/)
unless rows.empty?
  unversioned = rows.filter_map { |name, version| name unless version }
  specs = rows.to_h do |name, version, dir|
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = version || "0"
    end
    # Where the build found the gem, as an installed gem's directory
    # (lib/zr/manifest.rb). The JSON escapes only `"` and `\` in a path.
    if dir
      dir = dir.gsub(/\\(.)/, '\1')
      spec.instance_variable_set(:@full_gem_path, dir)
      spec.instance_variable_set(:@gem_dir, dir)
    end
    [name, spec]
  end

  # As bundler's setup adds them (Bundler::RubygemsIntegration#add_default_gems_to),
  # the default gems of the ruby tree that runs the program stand beside its
  # gems, so Gem.bin_path finds bundler's `bundle`. They stay stubs, which
  # read a gemspec only when something asks for the whole spec. A program
  # that no zr ran has no such tree, and no default gems.
  install = lambda do
    defaults = Gem::Specification.default_stubs.reject { |stub| specs.key?(stub.name) }
    record = Gem::Specification.specification_record
    record.all = specs.values
    record.instance_variable_set(:@stubs, specs.values + defaults)
    record.instance_variable_set(:@stubs_by_name, record.stubs.group_by(&:name))
    record.instance_variable_set(:@all, nil) unless defaults.empty?
  end
  install.call
  Gem.post_reset(&install)
  Gem.singleton_class.send(:define_method, :finish_resolve) { |*| [] }
  Gem.discover_gems_on_require = false

  specs.each_value do |spec|
    spec.activated = true
    Gem.loaded_specs[spec.name] = spec
  end

  Kernel.send(:define_method, :gem) do |dep, *requirements|
    requirements.pop if requirements.last.is_a?(Hash)
    dep = Gem::Dependency.new(dep, requirements) unless dep.respond_to?(:name) && dep.respond_to?(:requirement)
    spec = specs[dep.name]
    # A gem the program has none of: rubygems' own error, which counts
    # the gems it knows and names GEM_PATH.
    raise Gem::MissingSpecError.new(dep.name, dep.requirement) if spec.nil? && !unversioned.include?(dep.name)

    unless spec && dep.matches_spec?(spec)
      message = if unversioned.include?(dep.name)
                  "zr built this program with #{dep.name} from a directory that has no gemspec, so its version " \
                    "is unknown and does not match #{dep.requirement}. Give --gem #{dep.name}=DIR of a directory " \
                    "with a gemspec, then build again."
                else
                  "can't activate #{dep}, already activated #{spec.full_name}. " \
                    "Make sure all dependencies are added to Gemfile."
                end
      error = Gem::LoadError.new(message)
      error.name = dep.name
      error.requirement = dep.requirement
      raise error
    end
    # Each gem is active from the start, so rubygems' own `gem` answers
    # false for it, as ruby's does after a require of the gem.
    false
  end
  Kernel.send(:private, :gem)
end
