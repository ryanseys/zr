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

    def build(root)
      [onig(root)]
    end
  end
end
