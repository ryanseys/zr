# The debug gem sets a line breakpoint in a file before the file loads,
# then resolves it when the file loads (its :script_compiled event walks
# the file's code), and stops there and in a block.
require "debug"
puts "start"
require_relative "later"
puts later(3)
p each_twice([5])
