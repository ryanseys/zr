# A gem that a require loads before rubygems does is active once rubygems
# loads, in the order of the requires. Only the eval names Gem, so the
# requires run before rubygems loads in zr, as they run after it in ruby.
require "tsort"
require "shellwords"
require "abbrev"
p eval("Gem.loaded_specs.keys")
