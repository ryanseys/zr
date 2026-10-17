# A program that points rubygems at another gem directory (Gem.use_paths,
# as rubygems' own tests do) gets rubygems' answers from the gems there,
# as in ruby: the specifications, `gem`, and a require that activates a
# gem. The program's own gem (csv) stays loaded, and
# the first paths come back with Gem.clear_paths.
require "csv"
require "fileutils"
require "tmpdir"

def install(home, name, version)
  lib = File.join(home, "gems", "#{name}-#{version}", "lib")
  FileUtils.mkdir_p(lib)
  File.write(File.join(lib, "#{name}.rb"), "#{name.upcase} = #{version.inspect}\n")
  spec = Gem::Specification.new do |s|
    s.name = name
    s.version = version
    s.summary = "a gem of this test"
    s.authors = ["zr"]
    s.files = ["lib/#{name}.rb"]
  end
  FileUtils.mkdir_p(File.join(home, "specifications"))
  File.write(File.join(home, "specifications", "#{name}-#{version}.gemspec"), spec.to_ruby)
end

Dir.mktmpdir do |home|
  install(home, "zr_probe_a", "1.2")
  install(home, "zr_probe_a", "2.0")
  install(home, "zr_probe_b", "0.1")
  first = [Gem.dir, Gem.path]
  Gem.use_paths(home)
  p File.realpath(Gem.dir) == File.realpath(home), Gem.path.map { File.realpath(it) } == [File.realpath(home)]
  p Gem::Specification.find_all_by_name("zr_probe_a").map(&:full_name).sort
  # The list that the fake fetcher of rubygems' tests serves gemspecs from.
  p Gem::Specification.to_a.map(&:full_name).grep(/zr_probe/).sort
  p gem("zr_probe_a", "~> 1.0")
  p Gem.loaded_specs["zr_probe_a"].version.to_s
  begin
    gem "zr_probe_a", ">= 2"
  rescue Gem::LoadError => e
    p e.class
  end
  # A require of a file of an installed gem that is not active yet finds
  # the gem and activates it (Gem.discover_gems_on_require).
  name = "zr_probe_b"
  p require(name), ZR_PROBE_B, Gem.loaded_specs.key?(name)
  begin
    gem "zr_probe_missing"
  rescue Gem::MissingSpecError => e
    p e.class, e.name
  end
  Gem.clear_paths
  p [Gem.dir, Gem.path] == first
  p Gem::Specification.find_all_by_name("zr_probe_a").empty?
end
p gem("csv"), CSV.parse_line("a,b")
