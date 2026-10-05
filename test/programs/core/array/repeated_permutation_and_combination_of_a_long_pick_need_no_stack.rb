# A long pick walks with a loop: the first one comes at once, with no
# SystemStackError. A short pick keeps ruby's order.
p Array.new(100_000, nil).repeated_permutation(500_000) { break :ok }
p Array.new(100_000, nil).repeated_combination(500_000) { break :ok }
p [1, 2, 3].repeated_permutation(2).to_a
p [1, 2, 3].repeated_combination(2).to_a
p [1, 2].repeated_combination(3).to_a
p [:a].repeated_permutation(1).to_a
