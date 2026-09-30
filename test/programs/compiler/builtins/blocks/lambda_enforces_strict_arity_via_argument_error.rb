f = ->(x, y) { x + y }
begin
  f.call(1)
rescue ArgumentError => e
  puts "caught: #{e.message}"
end
puts f.call(1, 2)
