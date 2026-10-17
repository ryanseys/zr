# rubygems activates a gem when a require (or an autoload) first loads
# one of its files, and puts the gem's own directory on $LOAD_PATH. No
# gem is active before the first line.
p Gem.loaded_specs.keys
autoload :Shellwords, "shellwords"
Shellwords
p Gem.loaded_specs.keys
require "abbrev"
p Gem.loaded_specs.keys
abbrev = Gem.loaded_specs["abbrev"]
p abbrev.activated?, abbrev.default_gem?, abbrev.full_gem_path.delete_prefix(Gem.dir)
p $LOAD_PATH.include?(File.join(abbrev.full_gem_path, "lib"))
require "fileutils"
require "tsort"
p Gem.loaded_specs.keys
p Gem.loaded_specs["fileutils"].default_gem?, Gem.loaded_specs["tsort"].default_gem?
