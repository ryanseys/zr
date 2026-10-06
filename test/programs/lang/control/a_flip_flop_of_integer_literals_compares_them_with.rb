$VERBOSE = nil
r = []
(1..8).each { |i| $. = i; r << i if 2..4 }
p r
r = []
(1..8).each { |i| $. = i; r << i if 3...3 }
p r
r = []
(1..8).each { |i| $. = i; r << i if (i == 6)..7 }
p r
