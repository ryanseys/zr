# frozen_string_literal: true

require "fileutils"
require_relative "lib/zr/dev"
require_relative "../test/support/harness/reference"

module Zr
  module Dev
    # Sets up the ruby that the tests take every expected output from
    # (test/support/harness/reference.rb): ruby 4.0.7's bundled gems at
    # its own versions, and the gems whose C zr ports at zr's versions,
    # installed into tmp/reference/gems. bin/setup runs it.
    #
    #   zr-dev reference            install what is missing, then write the stamp
    #   zr-dev reference --check    fail when the directory is not current
    #
    # A gem with a C extension compiles here, once: this is the reference
    # ruby, not zr.
    class Reference < Command
      summary "Install the gems of the ruby that the tests compare with"
      usage "[--check]"
      host_ruby!

      Ref = Harness::Reference

      def defaults = @check = false

      def options(o) = o.on("--check", "install nothing; fail when tmp/reference is not current") { @check = true }

      def run(_argv)
        Dev.pinned!(name)
        if @check
          warn(Ref.ready? ? "#{Dev.rel(Ref::DIR)}: current" : "#{Dev.rel(Ref::DIR)}: not current; run `zr-dev reference`")
          return Ref.ready?
        end

        FileUtils.mkdir_p(Ref::GEMS)
        wanted = Ref.gems
        have = installed
        missing = wanted.reject { |gem, version| have.include?([gem, version]) }
        failed = missing.reject do |gem, version|
          puts "installing #{gem} #{version}"
          system({ "GEM_HOME" => Ref::GEMS, "GEM_PATH" => Ref::GEMS, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil },
                 Dev.ruby, "-S", "gem", "install", gem, "-v", version, "--install-dir", Ref::GEMS,
                 "--ignore-dependencies", "--no-document", "--quiet", out: File::NULL)
        end
        stale = installed.reject { |gem, version| wanted[gem] == version }
        stale.each { |gem, version| warn "#{Dev.rel(Ref::GEMS)} also holds #{gem} #{version}; remove it with `gem uninstall -i #{Dev.rel(Ref::GEMS)} #{gem} -v #{version}`" }
        failed.each_key { |gem| warn "zr-dev reference: #{gem} did not install" }
        return false unless failed.empty? && stale.empty?

        Paths.write_atomic(Ref::STAMP, Ref.stamp)
        puts "#{Dev.rel(Ref::DIR)}: #{wanted.size} gems, current"
        true
      end

      # `[[name, version]]` of each gem that GEMS holds, whatever its
      # platform (ffi installs as ffi-1.17.4-arm64-darwin).
      def installed
        Dir[File.join(Ref::GEMS, "specifications", "*.gemspec")].map do |path|
          spec = Gem::Specification.load(path)
          [spec.name, spec.version.to_s]
        end
      end
    end
  end
end
