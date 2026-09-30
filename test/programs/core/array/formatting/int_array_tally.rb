# Array#tally on an Integer array maps each distinct element to its
# count. The result is a Hash from Integer to Integer.
result = [1, 2, 2, 3, 3, 3].tally
puts result[1]
puts result[2]
puts result[3]
puts result.length
puts result.inspect
puts result.has_key?(2)
puts result.has_key?(99)
# A missing key gives nil, as in CRuby, so `== 0` is false.
puts result[99] == 0
