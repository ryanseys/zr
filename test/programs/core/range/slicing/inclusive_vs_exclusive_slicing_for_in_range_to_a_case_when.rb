# Range methods — first / last / include? / to_a / each, cover? /
# min / max / count, Range#map, inclusive-vs-exclusive distinction,
# step without block param. Was five separate tests; merged here.
# No class collisions. The only top-level def (`classify` in the
# inclusive/exclusive section) is unique within the file. Local
# names use per-section prefixes where the original tests reused
# generic names like `r`, `sum`, `i`.


ia = [10, 20, 30, 40, 50]
puts ia[1..3].length      # 3 (inclusive)
puts ia[1...3].length     # 2 (exclusive)
puts ia[1...3][0]         # 20
puts ia[1...3][1]         # 30

sa = "a,b,c,d,e".split(",")
puts sa[0..2].join(":")   # a:b:c
puts sa[0...2].join(":")  # a:b

fa = [1.5, 2.5, 3.5, 4.5]
puts fa[0..2].length      # 3
puts fa[0...2].length     # 2
puts fa[0...3].sum        # 7.5

s = "abcdef"
puts s[1..3]              # bcd
puts s[1...3]             # bc

sum_inc = 0
for ix in 1..3
  sum_inc = sum_inc + ix
end
puts sum_inc              # 6

sum_exc = 0
for ix in 1...3
  sum_exc = sum_exc + ix
end
puts sum_exc              # 3

puts (1..3).to_a.length   # 3
puts (1...3).to_a.length  # 2

def classify(n)
  case n
  when 0...10 then "small"
  when 10..99 then "medium"
  else "large"
  end
end
puts classify(5)
puts classify(9)
puts classify(10)
puts classify(99)
puts classify(100)
