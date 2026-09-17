# frozen_string_literal: true

# The generated files of vendor/ext/prism/lib, rendered from prism 1.9.0's
# config.yml and templates (vendored beside it) by prism's own driver,
# templates/template.rb. The gem's files (node.rb, serialize.rb and kin)
# come from upstream's templates; the Ruby backend's (lib/prism/ruby/*.rb)
# from ze0's.
#
#   ruby tools/prism_generate.rb           writes every generated file
#   ruby tools/prism_generate.rb --check   writes nothing, and fails when a
#                                          file differs from what the
#                                          templates render
require "fileutils"
require "tmpdir"

module PrismGenerate
  PRISM = File.expand_path("../vendor/ext/prism", __dir__)

  module_function

  # The files a template renders, relative to vendor/ext/prism.
  def names
    Dir.glob("lib/**/*.rb.erb", base: File.join(PRISM, "templates")).map { |erb| erb.delete_suffix(".erb") }.sort
  end

  # Renders every file, writes the ones that differ unless `check`, and
  # answers their names. The templates run with no locals of this file in
  # sight: ERB's top-level binding would share them.
  def run(check:)
    load File.join(PRISM, "templates/template.rb")
    Dir.mktmpdir("prism-generate-") do |dir|
      names.reject do |name|
        rendered = File.join(dir, name)
        Prism::Template.render(name, write_to: rendered)
        target = File.join(PRISM, name)
        same = File.exist?(target) && FileUtils.identical?(rendered, target)
        unless same || check
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(rendered, target)
        end
        same
      end
    end
  end
end

check = ARGV.include?("--check")
stale = PrismGenerate.run(check: check)
if check && !stale.empty?
  warn "stale: #{stale.join(", ")} (run ruby tools/prism_generate.rb)"
  exit 1
end
puts(stale.empty? ? "#{PrismGenerate.names.size} files current" : "wrote #{stale.join(", ")}")
