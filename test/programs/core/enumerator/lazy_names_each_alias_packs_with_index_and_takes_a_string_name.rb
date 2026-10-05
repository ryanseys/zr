# A lazy shows the alias that made it, with_index without a block yields
# the value and its index as two values, and to_enum takes a String name.
puts (1..10).lazy.map {}.collect {}.flat_map {}.collect_concat {}.select {}.find_all {}.filter {}.inspect

p (0..Float::INFINITY).lazy.with_index(2).map(&->(i, j) { [i - 1, j] }).take(2).to_a
p (0..Float::INFINITY).lazy.with_index(2).take(2).to_a

%w[with_index map select].each do |name|
  p [name, [1, 2, 3].to_enum.lazy.to_enum(name).first(2).to_a, [1, 2, 3].to_enum.lazy.to_enum(name.to_sym).first(2).to_a]
end
p [1, 2, 3].to_enum.lazy.to_enum("with_index", 10).first(2).to_a
