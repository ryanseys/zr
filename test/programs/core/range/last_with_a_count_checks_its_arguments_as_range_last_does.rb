# Range#last with arguments, as range_last takes them. With an Integer
# end (and no begin, or an Integer one), an empty range answers [] before
# it reads its arguments, and then the count must be one argument. Any
# other range makes its Array first, then Array#last checks 0..1. Found
# by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

class Two
  def to_int = 2
  def inspect = "Two"
end

[[(0...0), "0...0"], [(1..0), "1..0"], [(0...3), "0...3"], [(1..3), "1..3"], [(..4), "..4"], [(...4), "...4"],
 [("a".."c"), "'a'..'c'"], [(1.0..3.0), "1.0..3.0"], [(1..3.5), "1..3.5"]].each do |r, name|
  [[], [nil], [nil, 1], [2, 1], [2], [2.9], [Two.new], [0], [-1], [10], [[]]].each do |args|
    try("(#{name}).last(#{args.map(&:inspect).join(', ')})") { r.last(*args) }
  end
end

# An endless range raises first, whatever the arguments.
try("(1..).last") { (1..).last }
try("(1..).last(1, 2)") { (1..).last(1, 2) }

# A range whose each is its own takes the Array path.
class Steps < Range
  def each
    yield first
    yield self.end
  end
end
try("Steps.last(1)") { Steps.new(1, 9).last(1) }
try("Steps.last(1, 2)") { Steps.new(1, 9).last(1, 2) }
try("Steps.last(nil)") { Steps.new(1, 9).last(nil) }
