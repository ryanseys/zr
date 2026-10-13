#!/usr/bin/env ruby
# frozen_string_literal: true

# Installs the gems of the reference ruby: the ruby that the tests take
# every expected output from (test/support/harness/reference.rb). These
# are the pinned ruby's bundled gems at its own versions, and the gems
# whose C zr ports at zr's versions. They go into tmp/reference/gems.
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

abort "#{$PROGRAM_NAME}: the reference is ruby #{Zr::RUBY_PIN} (.ruby-version); this is #{RUBY_DESCRIPTION}" unless Zr.pinned_ruby?

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

# A precompiled gem carries a bundle for each released ruby ABI
# (ffi-1.17.4-arm64-darwin has lib/4.0/ffi_c.bundle), and a development
# ruby (RUBY_PATCHLEVEL -1) has none of them. Outside macOS a zr binary
# is static and links an extension from its objects, so it needs the
# objects of a build (google-protobuf-4.36.2-aarch64-linux-musl has only a
# .so). In both cases a gem installs from its source.
source = RUBY_PLATFORM.include?("darwin") && RUBY_PATCHLEVEL >= 0 ? [] : ["--platform", "ruby"]

# A clean environment, so that the bundle of this checkout does not apply.
env = { "GEM_HOME" => Ref::GEMS, "GEM_PATH" => Ref::GEMS, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
failed = wanted.reject { |gem, version| have.include?([gem, version]) }.reject do |gem, version|
  puts "installing #{gem} #{version}"
  # A gem that ruby bundles installs from ruby's own .gem: a ruby that is
  # not a release builds it from a commit, not as rubygems.org has it
  # (ruby 4.1's prism 1.9.0 is a later commit than the v1.9.0 release).
  bundled = File.join(Gem.default_dir, "cache", "#{gem}-#{version}.gem")
  what = File.file?(bundled) ? [bundled, "--local"] : [gem, "-v", version, *source]
  system(env, RbConfig.ruby, "-S", "gem", "install", *what, "--install-dir", Ref::GEMS,
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
# Each gem whose C extension zr runs as it is goes into a GEM_HOME of its
# own (Ref::NATIVE); its install compiles the extension (`source` above).
# extconf.rb's words for a gem outside macOS: Alpine's fortified headers
# stop zstd's C unless _FORTIFY_SOURCE is off.
build_args = RUBY_PLATFORM.include?("darwin") ? {} : { "zstd-ruby" => ["--", "--with-cflags=-U_FORTIFY_SOURCE"] }
failed += Ref::NATIVE.reject do |gem, version|
  home = Ref.native_home(gem, version)
  next true if Dir[File.join(home, "specifications", "#{gem}-#{version}*.gemspec")].any?

  puts "installing #{gem} #{version} into #{home}"
  # The build may run one of ruby's bundled gems (google-protobuf's
  # Rakefile runs rake).
  path = [home, Gem.default_dir].join(File::PATH_SEPARATOR)
  system(env.merge("GEM_HOME" => home, "GEM_PATH" => path), RbConfig.ruby, "-S", "gem", "install", gem, "-v", version, *source,
         "--install-dir", home, "--ignore-dependencies", "--no-document", "--quiet", *build_args.fetch(gem, []), out: File::NULL)
end.to_a
failed.each { |gem, _| warn "#{gem} did not install" }

stale = installed.reject { |gem, version| wanted[gem] == version }
stale.each do |gem, version|
  warn "#{Ref::GEMS} also holds #{gem} #{version}; " \
       "remove it with `gem uninstall -i #{Ref::GEMS} #{gem} -v #{version}`"
end
exit 1 unless failed.empty? && stale.empty?

File.write(Ref::STAMP, Ref.stamp)
puts "#{Ref::DIR}: #{wanted.size} gems, current"
