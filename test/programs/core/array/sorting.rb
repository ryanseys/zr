p [3, 1, 2].sort
p [3, 1, 2].sort { |a, b| b <=> a }
p %w[pear fig apple].sort
p [:b, :a, :c].sort
p [].sort, [1].sort
a = [5, 4, 3]
p a.sort!, a
p a.sort!.equal?(a)
# Ties: pairs that compare equal on their first element keep libc's order.
pairs = []
seed = 7
i = 0
while i < 200
  seed = (seed * 1103515245 + 12345) % 2147483648
  pairs << [seed % 5, i]
  i += 1
end
p pairs.sort { |x, y| x[0] <=> y[0] }.map { |x| x[1] }
p pairs.sort { |x, y| x[0] <=> y[0] }.map { |x| x[1] }[10, 30]
ten = pairs.first(10).sort { |x, y| x[0] <=> y[0] }
p ten
p pairs.first(30).sort { |x, y| x[0] <=> y[0] }
p pairs.first(41).sort { |x, y| x[0] <=> y[0] }.map { |x| x[1] }
p pairs.first(8).sort { |x, y| y[0] <=> x[0] }
p [3, 1, 2].sort { |a, b| (a <=> b) * 2 }
p [3, 1, 2].sort { |a, b| (a <=> b).to_s.to_sym == :"-1" ? -1 : 1 }
begin
  [3, "a", 2].sort
rescue ArgumentError => e
  p e
end
begin
  [3, nil, 2].sort
rescue ArgumentError => e
  p e
end
begin
  [1, 2, 3].sort { |a, b| raise "boom #{a} #{b}" }
rescue => e
  p e
end
begin
  [1, 2, 3].sort { |a, b| nil }
rescue ArgumentError => e
  p e
end
b = [3, 1, 2]
begin
  b.sort! { |x, y| raise "no" }
rescue => e
  p e, b
end
class Rev
  include Comparable
  attr_reader :n
  def initialize(n) = @n = n
  def <=>(o) = o.n <=> n
  def inspect = "Rev(#{n})"
end
p [Rev.new(1), Rev.new(3), Rev.new(2)].sort
p [1, 2, 3].sort { |a, b| [a, b].sort.first == a ? -1 : 1 }
a = [0, 1, 2, 3, 4, 5]
p a[1, 2], a[4, 10], a[6, 1], a[7, 1], a[-2, 2], a[-7, 2], a[2, -1], a[0, 0]
p a[1..3], a[1...3], a[2..], a[..2], a[-3..-1], a[4..1], a[6..], a[7..], a[-9..2], a[1..-1], a[2...-1]
p [5, 5, 5, 5, 5, 5, 5, 5, 5, 5].sort
p (1..60).to_a.reverse.sort
p pairs.sort_by { |x| x[0] }.map { |x| x[1] }
p pairs.first(17).sort_by { |x| x[0] }
p pairs.first(16).sort_by { |x| x[0] }
p pairs.first(5).sort_by { |x| x[0] }
p pairs.first(100).sort_by { |x| x[0] % 2 }.map { |x| x[1] }
p [3, 1, 2].sort_by { |x| -x }
p [1, 2, 3].sort_by { |x| x }
p %w[bb a ccc].sort_by(&:size)
p %w[bb a ccc].sort_by { |x| x }
p pairs.first(50).sort_by { |x| x[0].to_s }.map { |x| x[1] }
p pairs.first(50).sort_by { |x| [x[0] % 3, x[0]] }.map { |x| x[1] }
p({ b: 2, a: 1 }.sort_by { |k, v| v })
p({ b: 2, a: 1 }.sort)
p (1..5).sort { |a, b| b <=> a }
begin
  [1, "a"].sort_by { |x| x }
rescue ArgumentError => e
  p e
end
begin
  [1, 2].sort_by { |x| raise "in key" }
rescue => e
  p e
end
