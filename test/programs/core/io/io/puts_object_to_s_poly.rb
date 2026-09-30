# puts/print/interpolation of an object whose to_s returns a String on one
# branch and another type on the other must use the value to_s returns.
class Crash
  def initialize(flag) = @flag = flag
  def to_s = @flag ? "ok" : nil
end

puts Crash.new(true)
print Crash.new(true), "\n"
x = Crash.new(true)
puts "val=#{x}"
