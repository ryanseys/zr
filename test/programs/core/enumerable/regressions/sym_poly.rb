# A mixed-type array; `puts` on a Symbol element prints its name.
arr = [1, "two", :three, 4.0, true]
arr.each { |v| puts v }
