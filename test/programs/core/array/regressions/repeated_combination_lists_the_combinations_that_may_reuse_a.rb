# Array#repeated_combination(k) on an int array: k-element combinations
# allowing repeats, materialised as an array of arrays via .to_a.
p [1, 2].repeated_combination(2).to_a
p [1, 2, 3].repeated_combination(2).to_a
p [1, 2].repeated_combination(3).to_a
p [1, 2, 3].repeated_combination(1).to_a
