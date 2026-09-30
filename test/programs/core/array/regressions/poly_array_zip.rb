# Array#zip on mixed arrays gives an array of mixed pairs.
# inspect shows each element as its own type.
puts [1, "a"].zip([2, "b"]).inspect

# Three heterogeneous arrays
puts [1, "a", :s].zip([2, "b", :t]).inspect
