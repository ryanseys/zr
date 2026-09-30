# lrama-required features, in three parts of one coverage matrix.



# A10: Hash#transform_values (String keys, Integer values)
tv = {"a" => 1, "b" => 2, "c" => 3}
tv2 = tv.transform_values { |v| v * 10 }
puts tv2["a"]  # 10
puts tv2["b"]  # 20
puts tv2["c"]  # 30
puts tv["a"]   # 1  (original unchanged)

# A18: Array#zip
za = [1, 2, 3]
zb = [4, 5, 6]
zipped = za.zip(zb)
puts zipped.length  # 3

# Zip with different lengths
zc = [10, 20]
zipped2 = za.zip(zc)
puts zipped2.length  # 3

puts "done"
