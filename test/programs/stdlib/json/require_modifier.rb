# A bare-string `require` can have a trailing modifier (`rescue`,
# `if`, ...). The modifier attaches to the require and the program parses.
# (json/set are stdlib in the reference Ruby, so the rescue is a moot
# defensive guard there; the program does not use either library.)
require 'json' rescue nil
puts "ok1"
x = 5 rescue nil
puts x
require 'set' if false
puts "ok2"
