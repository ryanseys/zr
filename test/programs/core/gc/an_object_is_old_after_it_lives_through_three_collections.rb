require "objspace"
def flags(o) = ObjectSpace.dump(o)[/"flags":\{[^}]*\}/]
GC.disable
o = Object.new
s = +"str"
a = [1, 2]
5.times do |i|
  puts "#{i}: #{flags(o)} #{flags(s)} #{flags(a)}"
  GC.start
end
y = Object.new
o.instance_variable_set(:@y, y)
4.times do |i|
  puts "y#{i}: #{flags(y)}"
  GC.start(full_mark: false)
end
puts "y: #{flags(y)}"
