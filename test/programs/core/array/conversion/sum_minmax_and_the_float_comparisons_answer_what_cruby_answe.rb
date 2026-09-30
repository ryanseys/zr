# Array/Float/Integer conformance
p([1.1, 1.1, 2.2].uniq)          # Float array uniq
p Array.new                       # bare Array.new as direct p arg
a = []
p a.sum(0.0)                      # empty array sum with Float init
p([1, 2, 3].sum(0.5))             # Integer array sum with Float init
p([2, 2].all?(2))                 # all? with a value pattern
p([1, 2, 3].none?(4..9))          # none? with a Range pattern
p([1, 5, 3].any?(4..9))           # any? Range pattern
p(["ab", "cd"].none?(/a/))        # none? with a Regexp pattern
p(["ab", "cd"].any?(/a/))         # any? Regexp pattern
p((-0.0).abs)                     # Float#abs of negative zero
p((0.0 * -1.0).magnitude)         # Float#magnitude negative zero
p(5.downto(1.5).to_a)             # downto with a Float limit
p(1.upto(3.5).to_a)               # upto with a Float limit
