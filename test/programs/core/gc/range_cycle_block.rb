# Range#cycle block form: the counted form repeats the materialized int
# range n times; the argless form cycles forever until a block break.
a = []
(1..3).cycle(2) { |x| a << x }
p a

b = []
(0...3).cycle(1) { |x| b << x * 10 }
p b

n = 0
(1..5).cycle { |x| n += x; break if n > 20 }
p n

# argless Array#cycle
m = 0
[1, 2, 3].cycle { |x| m += x; break if m > 10 }
p m
