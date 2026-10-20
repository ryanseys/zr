# A program names ruby's library by the home that it runs with (ZR_HOME,
# which `zr run` sets), and zr compiled that library in below /zr. A
# require by the path on this machine finds the compiled file, so it
# loads once, as in ruby; File.exist? sees the file too.
require "fileutils"
path = File.join(RbConfig::CONFIG["rubylibdir"], "fileutils")
p require(path)
p $LOADED_FEATURES.count { |feature| feature.end_with?("/fileutils.rb") }
p File.exist?("#{path}.rb")
