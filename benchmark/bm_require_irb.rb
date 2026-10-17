# The start of a program that loads irb, as each child ruby of irb's own
# tests is: fileutils, delegate and the rest eval strings as they load.
# zr compiles them on the first run and maps them from its cache after
# (lib/zr/cache/loaded.rb), so the median is the start with the cache.
require "irb"
puts IRB::VERSION
