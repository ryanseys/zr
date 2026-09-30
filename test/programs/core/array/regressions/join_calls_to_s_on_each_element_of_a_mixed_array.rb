# Array#join on a mixed-element (poly) array: each element is to_s'd and
# joined with the separator. Each literal holds elements of more than
# one type.
puts [1, "x", :y].join(",")
puts [1, "x", :y].join
puts [10, "y"].join("-")
puts "done"
