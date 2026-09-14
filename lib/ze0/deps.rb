# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "paths"
require_relative "target"
require_relative "native/toolchain"

module Ze0
  # The vendored C dependencies, built with cc into static archives under
  # `Paths::BUILD`, one directory per target triple. A gem install builds them
  # (`ext/ze0/extconf.rb`); a checkout builds them on its first link.
  #
  # Each archive has a stamp beside it: the digest of every input's path
  # and bytes, this file, the flags and the toolchain's paths. An archive
  # whose stamp differs is built again. A stamp holds bytes, not times,
  # so a gem's extracted files, whatever their mtimes, never pass for a
  # build they are not.
  module Deps
    ZLIB_SOURCES = %w[adler32 crc32 deflate inffast inflate inftrees trees zutil].freeze
    ONIG_SOURCES = %w[regcomp regenc regerror regexec regext regparse regsyntax regtrav regversion st onig_init unicode unicode_fold1_key unicode_fold2_key unicode_fold3_key unicode_unfold_key ascii utf8].freeze

    # A build that cannot write where the archives go.
    class Unwritable < StandardError; end

    module_function

    # Where `target`'s archives live.
    def dir(target) = File.join(Paths::BUILD, target.triple)

    # Oniguruma for UTF-8 and ASCII: the archive's path.
    def onig(target = Target.default)
      src = File.join(Paths::VENDOR, "c/oniguruma")
      flags = ["-DHAVE_CONFIG_H", "-DONIG_DISABLE_DIRECT_THREADING", "-I#{src}"]
      archive(target, "libonig.a", Dir[File.join(src, "*.[ch]")], flags) do |objects|
        ONIG_SOURCES.map { |name| compile(File.join(src, "#{name}.c"), File.join(objects, "#{name}.o"), flags) }
      end
    end

    # zlib, the version ruby 4.0.6 links, so a deflate writes the bytes
    # ruby's writes: the archive's path.
    def zlib(target = Target.default)
      src = File.join(Paths::VENDOR, "c/zlib")
      flags = ["-DHAVE_UNISTD_H", "-I#{src}"]
      archive(target, "libz.a", Dir[File.join(src, "*.[ch]")], flags) do |objects|
        ZLIB_SOURCES.map { |name| compile(File.join(src, "#{name}.c"), File.join(objects, "#{name}.o"), flags) }
      end
    end

    # Prism, the parser ruby itself uses: the archive's path. The gem
    # carries its own sources, and every file under src builds.
    def prism(target = Target.default)
      src = File.join(Paths::VENDOR, "c/prism")
      flags = ["-std=c99", "-DPRISM_EXPORT_SYMBOLS=", "-I#{src}/include"]
      sources = Dir[File.join(src, "src/**/*.c")].sort
      archive(target, "libprism.a", sources + Dir[File.join(src, "include/**/*.h")], flags) do |objects|
        sources.map do |file|
          compile(file, File.join(objects, "#{file.delete_prefix("#{src}/src/").delete_suffix(".c").tr("/", "_")}.o"), flags)
        end
      end
    end

    # The archive `name`, built again from the objects the block compiles
    # when its stamp differs. One builder at a time holds the archive's
    # lock, and the archive is written under another name and renamed in:
    # a link that runs beside a build finds the old archive or the new
    # one, never none, and a builder that waited finds the new one made.
    # The stamp is written after the archive, so a build cut short leaves
    # a stamp that does not match.
    def archive(target, name, inputs, flags)
      home = dir(target)
      path = File.join(home, name)
      key = stamp(target, inputs, flags)
      return path if fresh?(path, key)

      begin
        FileUtils.mkdir_p(home)
        lock = File.open("#{path}.lock", File::RDWR | File::CREAT)
      rescue SystemCallError => e
        raise Unwritable, "the vendored archives in #{home} are missing or stale and cannot be built there " \
                          "(#{e.message}); run `gem pristine ze0`, or set ZE0_BUILD to a directory ze0 can write"
      end
      lock.flock(File::LOCK_EX)
      return path if fresh?(path, key)

      objects = File.join(home, File.basename(name, ".a"))
      FileUtils.mkdir_p(objects)
      partial = "#{path}.#{Process.pid}.tmp"
      File.delete(partial) if File.exist?(partial)
      log, ok = Native::Toolchain.run(["ar", "rcs", partial, *yield(objects)])
      raise "ar failed:\n#{log}" unless ok

      File.rename(partial, path)
      File.write("#{path}.digest.#{Process.pid}.tmp", key)
      File.rename("#{path}.digest.#{Process.pid}.tmp", "#{path}.digest")
      path
    ensure
      lock&.close
    end

    def fresh?(path, key)
      File.exist?(path) && File.exist?("#{path}.digest") && File.read("#{path}.digest") == key
    end

    def stamp(target, inputs, flags)
      digest = Digest::SHA256.new
      digest << target.triple << "\0"
      (inputs.sort + [__FILE__]).each { |file| digest << file << "\0" << File.binread(file) << "\0" }
      digest << flags.join("\0") << "\0" << Native::Toolchain.env.sort.flatten.join("\0")
      digest.hexdigest
    end

    def compile(source, object, flags)
      log, ok = Native::Toolchain.run(["cc", "-O2", "-c", *flags, source, "-o", object])
      raise "cc failed:\n#{log}" unless ok

      object
    end

    # `target`'s archives, built where they are stale.
    def build(target = Target.default)
      [onig(target), prism(target), zlib(target)]
    end
  end
end
