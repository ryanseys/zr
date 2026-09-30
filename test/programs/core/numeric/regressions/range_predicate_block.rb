# (a..b).any?/all?/none?/one? { |i| ... }
puts (0..5).all? {|i| i >= 0 }      # true
puts (0..5).all? {|i| i < 3 }       # false
puts (0..3).all? {|i| (0..3).cover?(i) }  # true

puts (0..5).any? {|i| i == 3 }      # true
puts (0..5).any? {|i| i > 100 }     # false

puts (0..5).none? {|i| i > 100 }    # true
puts (0..5).none? {|i| i == 3 }     # false

puts (0..5).one? {|i| i == 3 }      # true
puts (0..5).one? {|i| i >= 4 }      # false
puts (0..5).one? {|i| i > 100 }     # false
