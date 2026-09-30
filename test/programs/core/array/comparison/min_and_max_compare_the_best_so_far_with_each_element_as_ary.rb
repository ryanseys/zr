def t
  p yield
rescue ArgumentError => e
  puts e.message
end
a = [1, nil]
b = [1, "a"]
c = [2.0, nil]
t { a.min }
t { a.max }
t { b.min }
t { c.min }
t { a.minmax }
t { b.min { |x, y| x <=> y } }
