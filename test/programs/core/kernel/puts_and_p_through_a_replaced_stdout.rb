# puts, print and p reach whatever $stdout is: an object with only
# write, a StringIO, and a pipe with sync off; and puts of a String
# subclass, a symbol and an object with to_s take the line walk.
require "stringio"
class Sink
  attr_reader :got
  def initialize = @got = []
  def write(*parts) = (@got.concat(parts.map(&:to_s)); parts.sum { |x| x.to_s.bytesize })
end
old = $stdout
sink = $stdout = Sink.new
puts "a"
puts "b\n"
print "c", "d"
p 1, :two
puts [3, [4, nil]], nil
$stdout = old
p sink.got
$stdout = StringIO.new
puts "into a string"
puts "twice".dup << "!"
text = $stdout.string
$stdout = old
p text
class Line < String; end
class Thing
  def to_s = "thing"
end
puts Line.new("line"), :sym, Thing.new, 1.5, nil
r, w = IO.pipe
w.sync = false
w.puts "pipe"
w.print "no newline"
w.close
p r.read
$stdout.puts
STDOUT.print "x\n"
$stderr.puts "err"

