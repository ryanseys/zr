# max_by(n) returns tied elements in encounter order, descending by key. At
# the cut, it keeps the tied elements that come first.
a = [["Bob", 92], ["Eve", 92], ["Ann", 88]]
p a.max_by(2) { |x| x[1] }
b = [["Bob", 92], ["Eve", 92], ["Ann", 88], ["Zed", 92], ["Kim", 95]]
p b.max_by(3) { |x| x[1] }
p b.max_by(0) { |x| x[1] }
p [3, 1, 2].max_by(2) { |x| x }
p [1, 2].min_by(1) { |x| x }
