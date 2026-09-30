# MILESTONE: `require "bundler"` standalone, with nothing requiring rubygems
# first.
#
# The load checks three Ruby behaviors.
#
# `bundler.rb` requires `bundler/rubygems_ext` before rubygems. That file
# opens `module Gem`, but `defined?(Gem)` stays nil until its body runs.
# Thus the `require "rubygems" unless defined?(Gem)` line loads rubygems, and
# `Gem::Requirement` exists.
#
# `bundler/settings.rb` defines an unrelated `Path = Struct.new(...)`. The
# `class Git < Path` in `bundler/source/git.rb` resolves `Path` by its own
# lexical scope, so `Bundler::Source::Git` is one class.
#
# The `class Platform` body in `bundler/rubygems_ext.rb` is one
# `unless respond_to?(:generic)` over twelve constant writes. The condition
# runs with `self` bound to `Platform`, so ruby prints no warnings on stderr.
#
# The program prints shapes, never versions.

require "bundler"

p defined?(Bundler)
p Bundler::VERSION.is_a?(String)
p Bundler::VERSION.split(".").size >= 2
p Bundler.respond_to?(:setup)
p Bundler.respond_to?(:require)
p Bundler::LockfileParser.is_a?(Class)
p Bundler::Definition.is_a?(Class)
p Bundler::Dsl.is_a?(Class)
p Bundler.gem_version.is_a?(Gem::Version)
p Bundler.gem_version.to_s == Bundler::VERSION
