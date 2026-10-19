# A box starts with a copy of the load path as the program started with
# it. Its require of a Ruby library on its own load path runs that
# library's files again for the box, which lists them in its own
# features. A library with a C part (json) stays the program's.
$LOAD_PATH.unshift(File.expand_path("lib"))
require "counter"
Counter.bump

b = Ruby::Box.new
p b.load_path.include?(File.expand_path("lib"))
b.load_path.unshift(File.expand_path("lib"))
p b.require("counter")
p b::Counter.equal?(::Counter)
p [Counter.count, b::Counter.count]
b::Counter.bump
b::Counter.bump
p [Counter.count, b::Counter.count]
p b::Counter::Part.name
p b.require("counter")
p b.eval("$LOADED_FEATURES.grep(/counter/).map { File.basename(it) }")
p $LOADED_FEATURES.grep(/counter/).map { File.basename(it) }
p b.require("json")
p b::JSON.generate([1])
