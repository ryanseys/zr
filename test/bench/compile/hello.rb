# The bottom rung of the compile-cost ladder: a program with no require
# in it at all, so what this one times is the floor -- the front end on
# four lines, the backend on the toplevel, and the link.
puts "hello"
p 1 + 2
p [1, 2, 3].sum
p({ a: 1 }.keys)
