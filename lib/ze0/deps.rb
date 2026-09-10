# frozen_string_literal: true

module Ze0
  # The vendored C dependencies, built with cc into static archives under
  # vendor/build. A build is repeated when a source, or this file's source
  # list, is newer than the archive.
  module Deps
    ONIG_SOURCES = %w[regcomp regenc regerror regexec regext regparse regsyntax regtrav regversion st onig_init unicode unicode_fold1_key unicode_fold2_key unicode_fold3_key unicode_unfold_key ascii utf8].freeze

    module_function

    # Oniguruma for UTF-8 and ASCII: the archive's path.
    def onig(root)
      src = File.join(root, "vendor/c/oniguruma")
      out = File.join(root, "vendor/build")
      archive = File.join(out, "libonig.a")
      inputs = Dir[File.join(src, "*.[ch]")] + [__FILE__]
      return archive if File.exist?(archive) && inputs.all? { |f| File.mtime(f) <= File.mtime(archive) }

      objects = File.join(out, "onig")
      FileUtils.mkdir_p(objects)
      ONIG_SOURCES.each do |name|
        argv = ["cc", "-O2", "-c", "-DHAVE_CONFIG_H", "-DONIG_DISABLE_DIRECT_THREADING", "-I#{src}", File.join(src, "#{name}.c"), "-o", File.join(objects, "#{name}.o")]
        log = IO.popen(argv, err: %i[child out], &:read)
        raise "cc failed on #{name}.c:\n#{log}" unless $?.success?
      end
      File.delete(archive) if File.exist?(archive)
      log = IO.popen(["ar", "rcs", archive, *ONIG_SOURCES.map { |name| File.join(objects, "#{name}.o") }], err: %i[child out], &:read)
      raise "ar failed:\n#{log}" unless $?.success?

      archive
    end

    # Prism, the parser ruby itself uses: the archive's path. The gem
    # carries its own sources, and every file under src builds.
    def prism(root)
      src = File.join(root, "vendor/c/prism")
      out = File.join(root, "vendor/build")
      archive = File.join(out, "libprism.a")
      sources = Dir[File.join(src, "src/**/*.c")].sort
      inputs = sources + Dir[File.join(src, "include/**/*.h")] + [__FILE__]
      return archive if File.exist?(archive) && inputs.all? { |f| File.mtime(f) <= File.mtime(archive) }

      objects = File.join(out, "prism")
      FileUtils.mkdir_p(objects)
      names = sources.map do |file|
        name = file.delete_prefix("#{src}/src/").delete_suffix(".c").tr("/", "_")
        object = File.join(objects, "#{name}.o")
        argv = ["cc", "-O2", "-std=c99", "-c", "-DPRISM_EXPORT_SYMBOLS=", "-I#{src}/include", file, "-o", object]
        log = IO.popen(argv, err: %i[child out], &:read)
        raise "cc failed on #{file}:\n#{log}" unless $?.success?

        object
      end
      File.delete(archive) if File.exist?(archive)
      log = IO.popen(["ar", "rcs", archive, *names], err: %i[child out], &:read)
      raise "ar failed:\n#{log}" unless $?.success?

      archive
    end

    def build(root)
      [onig(root), prism(root)]
    end
  end
end
