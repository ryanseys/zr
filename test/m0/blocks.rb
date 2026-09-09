x = 1
[10, 20].each { |a| y = a; x += 1; [2].each { |d| y = d + x; p [a, y] } }
p x
def m
  yield 1, 2
  return 3 if block_given?
  4
end
p(m { |k, j| p [k, j]; next k })
def with_break
  r = [1, 2, 3].each { |v| break v * 10 if v == 2 }
  p r
  [1, 2, 3].each { |v| return v if v == 2 }
  :never
end
p with_break
3.times { |i| puts i }
p [1, 2, 3].map { |v| v * v }, [1, 2, 3, 4].select { |v| v % 2 == 0 }, [1, 2, 3].reject { |v| v > 1 }
[[1, 2], [3, 4]].each { |a, b| p a + b }
[[1, 2]].each_with_index { |a, i| p i }
n = 0
loop do
  n += 1
  break if n > 4
end
p n
1.upto(3) { |i| print_it = i; p print_it }
p [1, 2].each { |v| }
def deep
  [1].each { [2].each { yield 5 } }
end
deep { |v| p v }
pr = [1].each { |v| }
def esc
  [1].each { |v| return 9 } 
end
p esc
[1, 2].each do |v|
  next if v == 1
  p v
end
i = 0
while i < 5
  i += 1
  next if i == 2
  break if i == 4
  p i
end
[1].each { |v| raise_it }
