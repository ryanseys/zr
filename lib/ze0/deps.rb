# frozen_string_literal: true

require_relative "native/toolchain"

module Ze0
  # The vendored C dependencies, built with cc into static archives under
  # vendor/build. A build is repeated when a source, or this file's source
  # list, is newer than the archive.
  module Deps
    ZLIB_SOURCES = %w[adler32 crc32 deflate inffast inflate inftrees trees zutil].freeze
    ONIG_SOURCES = %w[regcomp regenc regerror regexec regext regparse regsyntax regtrav regversion st onig_init unicode unicode_fold1_key unicode_fold2_key unicode_fold3_key unicode_unfold_key ascii utf8].freeze

    module_function

    # Oniguruma for UTF-8 and ASCII: the archive's path.
    def onig(root)
      src = File.join(root, "vendor/c/oniguruma")
      out = File.join(root, "vendor/build")
      archive(File.join(out, "libonig.a"), Dir[File.join(src, "*.[ch]")] + [__FILE__]) do
        objects = File.join(out, "onig")
        FileUtils.mkdir_p(objects)
        ONIG_SOURCES.map do |name|
          object = File.join(objects, "#{name}.o")
          cc(["-DHAVE_CONFIG_H", "-DONIG_DISABLE_DIRECT_THREADING", "-I#{src}", File.join(src, "#{name}.c"), "-o", object])
          object
        end
      end
    end

    # zlib, the version ruby 4.0.6 links, so a deflate writes the bytes
    # ruby's writes: the archive's path.
    def zlib(root)
      src = File.join(root, "vendor/c/zlib")
      out = File.join(root, "vendor/build")
      archive(File.join(out, "libz.a"), Dir[File.join(src, "*.[ch]")] + [__FILE__]) do
        objects = File.join(out, "zlib")
        FileUtils.mkdir_p(objects)
        ZLIB_SOURCES.map do |name|
          object = File.join(objects, "#{name}.o")
          cc(["-DHAVE_UNISTD_H", "-I#{src}", File.join(src, "#{name}.c"), "-o", object])
          object
        end
      end
    end

    # Prism, the parser ruby itself uses: the archive's path. The gem
    # carries its own sources, and every file under src builds.
    def prism(root)
      src = File.join(root, "vendor/c/prism")
      out = File.join(root, "vendor/build")
      sources = Dir[File.join(src, "src/**/*.c")].sort
      inputs = sources + Dir[File.join(src, "include/**/*.h")] + [__FILE__]
      archive(File.join(out, "libprism.a"), inputs) do
        objects = File.join(out, "prism")
        FileUtils.mkdir_p(objects)
        sources.map do |file|
          object = File.join(objects, "#{file.delete_prefix("#{src}/src/").delete_suffix(".c").tr("/", "_")}.o")
          cc(["-std=c99", "-DPRISM_EXPORT_SYMBOLS=", "-I#{src}/include", file, "-o", object])
          object
        end
      end
    end

    # The archive at `path`, built again from the objects the block
    # compiles when an input is newer. One builder at a time holds the
    # archive's lock, and the archive is written under another name and
    # renamed in: a link that runs beside a build finds the old archive
    # or the new one, never none, and a builder that waited finds the
    # new one made.
    def archive(path, inputs)
      return path if fresh?(path, inputs)

      FileUtils.mkdir_p(File.dirname(path))
      File.open("#{path}.lock", File::RDWR | File::CREAT) do |lock|
        lock.flock(File::LOCK_EX)
        return path if fresh?(path, inputs)

        partial = "#{path}.#{Process.pid}.tmp"
        File.delete(partial) if File.exist?(partial)
        log, ok = Native::Toolchain.run(["ar", "rcs", partial, *yield])
        raise "ar failed:\n#{log}" unless ok

        File.rename(partial, path)
      end
      path
    end

    def fresh?(path, inputs)
      File.exist?(path) && inputs.all? { |f| File.mtime(f) <= File.mtime(path) }
    end

    def cc(args)
      log, ok = Native::Toolchain.run(["cc", "-O2", "-c", *args])
      raise "cc failed:\n#{log}" unless ok
    end

    def build(root)
      [onig(root), prism(root), zlib(root)]
    end
  end
end
