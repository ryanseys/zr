# In `require "x"; code` on one line, the code after the require runs.
puts "start"
require "json"; puts JSON.generate([1, 2, 3])
