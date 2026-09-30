# A local that holds an Integer or nil (from String#index, rindex,
# find_index). After `return -1 if h.nil?`, the rest of the scope
# sees `h` as an Integer, so `h + 1` is integer arithmetic and the
# method returns an Integer.
#
# `lookup` uses the result of find_or_neg as an array index.

ARR = [10, 20, 30, 40, 50, 60]

def find_or_neg(s, needle)
  h = s.index(needle)
  return -1 if h.nil?
  h + 1
end

def lookup(s, needle)
  i = find_or_neg(s, needle)
  return 0 if i < 0
  ARR[i]
end

puts find_or_neg("abcdef", "b")
puts find_or_neg("abcdef", "z")
puts lookup("abcdef", "b")
puts lookup("abcdef", "a")
puts lookup("abcdef", "z")
