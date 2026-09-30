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
# call (runtime/core/kernel.rb) does the same.
# A `--gem` directory with no gemspec has no version (null), and here
# counts as version 0.
rows = Primitive.zr_load_names(9).scan(/\{"name":"([^"]+)","version":(?:"([^"]+)"|null)/)
unless rows.empty?
  unversioned = rows.filter_map { |name, version| name unless version }
  specs = rows.to_h do |name, version|
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = version || "0"
    end
    [name, spec]
  end

  Gem::Specification.all = specs.values
  Gem.post_reset { Gem::Specification.all = specs.values }
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
    unless spec && dep.matches_spec?(spec)
      message = if unversioned.include?(dep.name)
                  "zr built this program with #{dep.name} from a directory that has no gemspec, so its version " \
                    "is unknown and does not match #{dep.requirement}. Give --gem #{dep.name}=DIR of a directory " \
                    "with a gemspec, then build again."
                elsif spec
                  "can't activate #{dep}, already activated #{spec.full_name}. " \
                    "Make sure all dependencies are added to Gemfile."
                else
                  "#{dep.name} is not part of this program: zr built it without #{dep.name}. " \
                    "Add #{dep.name} to the Gemfile, or give --gem #{dep.name}=DIR, then build again."
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
