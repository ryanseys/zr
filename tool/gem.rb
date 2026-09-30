# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require_relative "lib/zr/dev"

module Zr
  module Dev
    # Builds a platform gem: the `ruby` gem's files, and the compiled
    # compiler for one platform with its manifest (lib/zr/shipped.rb). The
    # user's first build then needs no self-build. This is a spike; see
    # docs/how-to/release.md for the plan and the numbers.
    #
    #   zr-dev gem native                       pkg/zr-<version>-arm64-darwin.gem
    #   zr-dev gem native --install /opt/zr     ... and install it there, then
    #                                           build a program with it
    #
    # It packs `bin/zr` (`rake build:self`), so it builds for this host's
    # platform only. That binary finds its runtime files through the
    # checkout's path (`Paths::ROOT` comes from `__dir__`), so it holds
    # this machine's path, and pack refuses it. `--local` packs it for a
    # test on this machine; never publish such a gem. A gem to publish
    # waits for a compiled compiler that finds its files from where it is
    # installed (docs/how-to/release.md).
    class PlatformGem < Command
      summary "Build the platform gem, with the compiled compiler in it"
      usage "native [--install DIR] [--local]"
      # It builds the gem with rubygems, which a zr binary does not have.
      host_ruby!

      def options(o)
        o.on("--install DIR", "Install the gem into DIR, and build a program with it") { |v| @install = v }
        o.on("--local", "Pack a binary that holds this checkout's path, for a test here only") { @local = true }
      end

      def run(argv)
        fail!("give the kind of gem: native") unless argv == ["native"]
        require "rubygems/package"
        require_relative "../lib/zr/compiled_compiler"
        cc = CompiledCompiler
        fail!("#{rel(cc.binary)} is not current; run `rake build:self` first") unless cc.current?
        publishable!(cc.binary)

        platform = Gem::Platform.local
        platform = Gem::Platform.new([platform.cpu, platform.os])
        gem = pack(cc, platform.to_s)
        puts format("%s: %.1f MB (the binary alone: %.1f MB)", rel(gem), File.size(gem) / 1e6, File.size(cc.binary) / 1e6)
        smoke(gem, "zr-#{VERSION}-#{platform}") if @install
      end

      # Writes `exe/<platform>/` for the gem, builds the gem into pkg/, and
      # removes `exe/<platform>/` again. Returns the gem's path.
      def pack(cc, platform)
        dir = Dev.path("exe/#{platform}")
        FileUtils.mkdir_p(dir)
        spec = Gem::Specification.load(Dev.path("zr.gemspec"))
        # The binary keeps its name: its ad hoc signature includes it.
        FileUtils.cp(cc.binary, File.join(dir, "zr"))
        manifest = Shipped.manifest(shipped_sources(cc, spec), platform)
        fail!("the manifest names ruby #{manifest[/^ruby (.*)$/, 1]}, not #{RUBY}") unless manifest.include?("\nruby #{RUBY}\n")
        File.write(File.join(dir, "zr.manifest"), manifest)
        spec.platform = Gem::Platform.new(platform)
        # `git ls-files` does not list them, because git ignores them.
        spec.files += ["exe/#{platform}/zr", "exe/#{platform}/zr.manifest"]
        FileUtils.mkdir_p(Dev.path("pkg"))
        built = Dir.chdir(ROOT) { Gem::Package.build(spec) }
        Dev.path("pkg/#{built}").tap { |gem| FileUtils.mv(Dev.path(built), gem) }
      ensure
        FileUtils.rm_rf(dir) if dir
      end

      # The compiler's sources that the gem contains. A checkout has more
      # files under lib/, runtime/ and vendor/ (vendor/bundle, files that
      # git ignores), and an installed gem has only these, so the digest
      # covers only these.
      def shipped_sources(cc, spec)
        files = spec.files.to_set
        cc.sources.select { |f| !f.start_with?("#{ROOT}/") || files.include?(rel(f)) }
      end

      # Installs `gem` into `@install` and builds a program with the
      # installed zr. The first build checks the manifest's digest, and
      # records that in the user's cache, so the record shows that the
      # shipped binary ran the build.
      def smoke(gem, full_name)
        Dev.run!("gem", "install", "--local", "--ignore-dependencies", "--no-document", "--install-dir", @install, gem)
        Dir.mktmpdir("zr-gem-") do |work|
          File.write(File.join(work, "hello.rb"), "puts [1, 2, 3].sum\n")
          env = { "GEM_HOME" => @install, "GEM_PATH" => [@install, *Gem.path].join(File::PATH_SEPARATOR), "RUBYOPT" => nil,
                  "BUNDLE_GEMFILE" => nil }
          began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          Dev.run!(env, File.join(@install, "bin/zr"), "build", "hello.rb", "-o", "hello", chdir: work)
          took = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began
          out = IO.popen([File.join(work, "hello")], &:read)
          fail!("the installed zr built a program that printed #{out.inspect}") unless out == "6\n"
          root = File.join(@install, "gems", full_name)
          verified = File.join(Paths.user_cache, "shipped-#{VERSION}-#{Digest::SHA256.hexdigest(root)[0, 12]}", "verified.marshal")
          fail!("the installed zr did not use its shipped binary (no #{verified})") unless File.exist?(verified)
          puts format("installed in %s; the shipped binary built a program in %.1f s, and it ran", @install, took)
        end
      end

      # Stops unless `--local`, when the binary holds this checkout's path:
      # a gem with it would carry the path of the machine that built it.
      def publishable!(binary)
        return if @local || !File.binread(binary).include?(ROOT.b)

        fail!("#{rel(binary)} holds this checkout's path (#{ROOT}), so no gem to publish can carry it. " \
              "--local packs it for a test on this machine")
      end

      def rel(path) = Dev.rel(path)
    end
  end
end
