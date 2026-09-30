obj = Object.new
def obj.combine(a, b)
  yield a, b, a + b
end
obj.combine(2, 3) { |x, y, s| puts "#{x} #{y} #{s}" }
