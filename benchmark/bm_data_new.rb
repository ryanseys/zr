# data-new benchmark: a Data made by position and by keyword
Point = Data.define(:x, :y)

sum = 0
i = 0
while i < 1000000
  sum += Point.new(i, 1).x
  sum += Point.new(x: 2, y: i).y
  i += 1
end
puts sum
puts "done"
