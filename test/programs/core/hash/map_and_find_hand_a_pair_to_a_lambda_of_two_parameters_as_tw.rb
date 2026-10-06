h = { a: 1, b: 2 }
p h.map(&lambda { |k, v| [v, k] })
p h.find(&lambda { |k, v| v == 2 })
begin
  h.each(&lambda { |k, v| p [k, v] })
rescue ArgumentError => e
  p [:each, e.message]
end
begin
  p h.select(&lambda { |k, v| v > 1 })
rescue ArgumentError => e
  p [:select, e.message]
end
begin
  p h.count(&lambda { |k, v| v > 1 })
rescue ArgumentError => e
  p [:count, e.message]
end
