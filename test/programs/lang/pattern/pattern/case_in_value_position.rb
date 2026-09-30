# case/in used as a value: assignment RHS, method receiver, and method-return
# position. Each gives the value of the matched arm.

def describe(x)
  s = case x
      in [a, b] then "pair #{a},#{b}"
      in [a] then "one #{a}"
      else "other"
      end
  s
end
puts describe([1, 2])
puts describe([5])
puts describe([])

def total(x)
  (case x
   in [a, b] then [a, b]
   else [0]
   end).sum
end
p total([3, 4])
p total([9])
