#!/usr/bin/env ruby
# frozen_string_literal: true

# Installs the gems of the reference ruby: the ruby that the tests take
# every expected output from (test/support/harness/reference.rb). These
# are ruby 4.0.7's bundled gems at its own versions, and the gems whose C
# zr ports at zr's versions. They go into tmp/reference/gems.
#
#   ruby tool/install_reference_gems.rb
#
# The script installs only the gems that are missing. When all gems are
# there, and no other versions are, it writes tmp/reference/STAMP. The
# tests start only when that stamp is current. bin/setup runs this script.
#
# A gem with a C extension compiles here, once: this is the reference
# ruby, not zr.

require "fileutils"
require "rubygems"
require "rbconfig"
require_relative "../test/support/harness/reference"

Ref = Zr::Harness::Reference

pinned = File.read(File.expand_path("../.ruby-version", __dir__)).strip
abort "#{$PROGRAM_NAME}: the reference is ruby #{pinned}; this is ruby #{RUBY_VERSION}" unless RUBY_VERSION == pinned

# `[[name, version]]` of each gem in the directory, whatever its platform
# (ffi installs as ffi-1.17.4-arm64-darwin).
def installed
  Dir[File.join(Ref::GEMS, "specifications", "*.gemspec")].map do |path|
    spec = Gem::Specification.load(path)
    [spec.name, spec.version.to_s]
  end
end

FileUtils.mkdir_p(Ref::GEMS)
wanted = Ref.gems
have = installed

# A clean environment, so that the bundle of this checkout does not apply.
env = { "GEM_HOME" => Ref::GEMS, "GEM_PATH" => Ref::GEMS, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
failed = wanted.reject { |gem, version| have.include?([gem, version]) }.reject do |gem, version|
  puts "installing #{gem} #{version}"
  system(env, RbConfig.ruby, "-S", "gem", "install", gem, "-v", version, "--install-dir", Ref::GEMS,
         "--ignore-dependencies", "--no-document", "--quiet", out: File::NULL)
end
# Each other version of a ported gem that a program test runs with goes
# into a GEM_HOME of its own (Ref::PORTS).
failed = failed.to_a + Ref.ports.reject do |gem, version|
  home = Ref.port_home(gem, version)
  next true if File.directory?(Ref.port_gem(gem, version))

  puts "installing #{gem} #{version} into #{home}"
  system(env.merge("GEM_HOME" => home, "GEM_PATH" => home), RbConfig.ruby, "-S", "gem", "install", gem, "-v", version,
         "--install-dir", home, "--ignore-dependencies", "--no-document", "--quiet", out: File::NULL)
end
failed.each { |gem, _| warn "#{gem} did not install" }

stale = installed.reject { |gem, version| wanted[gem] == version }
stale.each do |gem, version|
  warn "#{Ref::GEMS} also holds #{gem} #{version}; " \
       "remove it with `gem uninstall -i #{Ref::GEMS} #{gem} -v #{version}`"
end
exit 1 unless failed.empty? && stale.empty?

File.write(Ref::STAMP, Ref.stamp)
puts "#{Ref::DIR}: #{wanted.size} gems, current"
