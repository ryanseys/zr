def t
  p yield
rescue ArgumentError => e
  puts e.message
end
x = "a"
a = [1, nil]
t { [1, "a"].min }
t { [1, x, 2].min }
t { [1, nil].min }
t { [1, "a"].max }
t { a.min }
t { [1, "a"].min { |p, q| p <=> q } }
t { [3, 1, 2].min }
t { [3, 1, x.size + 5].max }
class Array
  def min = :redefined
end
t { [1, x].min }
