# Array#shuffle keeps all the elements of a Symbol array and of a
# mixed array.

# Symbol array
sa = [:a, :b, :c, :d].shuffle
puts sa.length

# Mixed array
pa = [1, "a", :s, 2.0].shuffle
puts pa.length
