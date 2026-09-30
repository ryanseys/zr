# An #inspect built in a temporary string builder must hand back a string of
# its own, not the builder's buffer.
#
# After the builder is gone, the result must stay alive. The example holds
# each result across a GC.start and then reads it back.

def churn
  a = []
  300.times { |i| a.push("filler #{i}") }
  a.length
end

def through_gc(s)
  churn
  GC.start
  churn
  GC.start
  s
end

p through_gc("abc".match(/b/).inspect)
p through_gc([[1, 2], [3]].inspect)
p through_gc([["a"], ["b"]].inspect)
p through_gc([[1.5], [2.5]].inspect)
p through_gc([[:a], [:b]].inspect)
p through_gc([[1, "x"], [nil]].inspect)
p through_gc({ 1 => 2, 3 => 4 }.inspect)

# the same result kept in a container rather than a local
box = []
box.push("a1b2".match(/(\d)(\w)/).inspect)
box.push([[7, 8]].inspect)
churn
GC.start
churn
GC.start
p box
