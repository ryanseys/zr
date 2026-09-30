arr = [1.5, 2.5, 0.5, 3.5]
puts arr.min     # 0.5
puts arr.max     # 3.5
puts arr.first   # 1.5
puts arr.last    # 3.5

neg = [-1.5, -3.25, 2.75]
puts neg.min     # -3.25
puts neg.max     # 2.75

one = [4.5]
puts one.min     # 4.5
puts one.max     # 4.5

# Sum with non-integer-valued result (avoids the stale-type truncation
# that would print "4" instead of "4.5").
sum = [1.5, 2.5, 0.5]
puts sum.sum     # 4.5
