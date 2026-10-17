# rubygems' require finds a file in a gem of the directories that the
# program points rubygems at, activates that gem and loads the file, as
# rubygems' own tests do (Gem.discover_gems_on_require). The file is made
# at run time, so the program compiles it then: the eval below makes the
# compiler part of the program.
require "fileutils"
require "tmpdir"

def install(home, name, version, deps = {})
  lib = File.join(home, "gems", "#{name}-#{version}", "lib")
  FileUtils.mkdir_p(lib)
  File.write(File.join(lib, "#{name}_lib.rb"), "#{name.upcase}_LIB = #{version.inspect}\n")
  spec = Gem::Specification.new do |s|
    s.name = name
    s.version = version
    s.summary = "a gem of this test"
    s.authors = ["zr"]
    s.files = ["lib/#{name}_lib.rb"]
    deps.each { |dep, req| s.add_dependency(dep, req) }
  end
  FileUtils.mkdir_p(File.join(home, "specifications"))
  File.write(File.join(home, "specifications", "#{name}-#{version}.gemspec"), spec.to_ruby)
end

eval("1")
Dir.mktmpdir do |home|
  install(home, "zr_probe_a", "1.0")
  install(home, "zr_probe_a", "2.0")
  install(home, "zr_probe_c", "1.0", "zr_probe_a" => "< 2")
  Gem.use_paths(home)
  p Gem.discover_gems_on_require
  # The newest version that holds the file.
  p require("zr_probe_a_lib"), ZR_PROBE_A_LIB, Gem.loaded_specs["zr_probe_a"].version.to_s
  p require("zr_probe_a_lib")
  # A gem whose dependency is already active at a version it does not
  # accept cannot be activated.
  begin
    require "zr_probe_c_lib"
  rescue Gem::LoadError => e
    p e.class
  end
  begin
    require "zr_probe_missing_lib"
  rescue LoadError => e
    p e.class, e.path
  end
  Gem.clear_paths
end
