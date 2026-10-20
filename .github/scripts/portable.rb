# frozen_string_literal: true

# Installs the gem at two paths of different lengths, builds and exports
# this host's runtime in each, with a cache of its own, and checks that
# the two bundles name the same files with the same bytes: a runtime has
# no path of its install (lib/zr/paths.rb, `Paths.portable`), so the
# bundle that a release builds serves every install.
#
#   ruby .github/scripts/portable.rb zr-X.Y.Z.gem

require "json"
require "tmpdir"
require "zlib"

gem = File.expand_path(ARGV.fetch(0))
version = File.basename(gem)[/\Azr-(.+)\.gem\z/, 1] or abort "portable: name the zr gem, zr-X.Y.Z.gem"

# The manifest of a bundle (lib/zr/prebuilt.rb): its files, and its roots.
def manifest(bundle)
  Zlib::GzipReader.open(bundle) do |gz|
    gz.gets
    data = JSON.parse(gz.gets)
    [data.fetch("files").to_h { |row| [row.fetch("path"), row.fetch("sha256")] }, data.fetch("roots")]
  end
end

Dir.mktmpdir("zr-portable-") do |dir|
  installs = %w[a a/much/longer/path/to/the/gems].map do |place|
    home = File.join(dir, place)
    system("gem", "install", "--local", "--no-document", "--install-dir", home, gem, exception: true, out: File::NULL)
    zr = File.join(home, "gems", "zr-#{version}", "exe", "zr")
    bundle = File.join(dir, "#{place.tr("/", "-")}.zrr")
    system({ "ZR_CACHE" => File.join(dir, "cache-#{place.tr("/", "-")}") }, RbConfig.ruby, zr, "cache", "export", "-o", bundle, exception: true)
    manifest(bundle)
  end
  (files_a, roots_a), (files_b, roots_b) = installs
  differ = (files_a.keys | files_b.keys).sort.reject { |path| files_a[path] == files_b[path] }
  differ.each { |path| puts "portable: #{path}: #{files_a[path] || "missing"} and #{files_b[path] || "missing"}" }
  puts "portable: the roots differ" unless roots_a == roots_b
  abort "portable: the two installs built other runtimes" unless differ.empty? && roots_a == roots_b

  puts "portable: both installs built the same #{files_a.size} file(s)"
end
