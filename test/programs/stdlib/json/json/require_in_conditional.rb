# A `require` inside an `if`, inside a method body, or in value position
# works like a top-level one. It is not an error.

if 1 > 0
  require "set"
end

def helper
  require "json"
  "ok"
end

x = require("set")
puts helper
puts "done"
