r = Ractor.new(20, 22) do |a, b|
  a + b
end
puts r.value
