# MILESTONE: `require "rubygems"` then `require "bundler"`, and the bundler
# monkeypatches over RubyGems that the second require installs.
#
# Ruby prints no `already initialized constant Gem::Platform::X` warning.
# `bundler/rubygems_ext.rb:54`'s `class Platform` body is a single
# `unless respond_to?(:generic)` statement. That guard asks about the class,
# not about the enclosing `Gem`, so no Platform constant is written twice.
#
# A golden compares stdout AND stderr, so a stray warning fails it.
#
# Shapes, never versions.

require "rubygems"
require "bundler"

p defined?(Gem)
p defined?(Bundler)
p Bundler::VERSION.is_a?(String)
p Bundler.respond_to?(:setup)
p Bundler.gem_version.is_a?(Gem::Version)

# Bundler's monkeypatches over RubyGems landed.
p Gem::Specification.new.respond_to?(:source)
p Gem::Platform.respond_to?(:generic)
p Gem::Platform.generic(Gem::Platform::RUBY).to_s

# The lockfile reader -- pure text, and what every `bundle` command starts at.
lock = <<~LOCK
  GEM
    remote: https://rubygems.org/
    specs:
      rake (13.2.1)
      minitest (5.25.1)

  PLATFORMS
    ruby

  DEPENDENCIES
    minitest (~> 5.0)
    rake

  BUNDLED WITH
     2.5.0
LOCK
parsed = Bundler::LockfileParser.new(lock)
p parsed.specs.map { |s| [s.name, s.version.to_s] }.sort
p parsed.platforms.map(&:to_s)
p parsed.dependencies.keys.sort
p parsed.bundler_version.to_s
