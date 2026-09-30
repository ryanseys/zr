# An arrow lambda (`-> {}`) that returns a string literal gives back that
# string when called.
f = -> { "arrow" }
puts f.call

g = -> { 7 }
puts g.call
