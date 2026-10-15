# An endless String Range walks a plain copy of its begin by succ, taken
# before each yield, so a block that changes the String it gets does not
# move the walk. Digits count up at the begin's width in US-ASCII.
start = String.new("b")
(start..).each { |x| x << "!"; print x, " "; break if x.start_with?("d") }
puts
p start

class Tag < String; end
(Tag.new("y")..).each { |x| p [x, x.class]; break if x == "aa" }

walked = []
("08"..).each { |x| walked << [x, x.encoding]; break if walked.size == 4 }
p walked
p ("9"..).first(3), ("zz"..).first(2), ("a9"..).first(3)
p (:x..).first(4)

class Ender < String
  def succ = String.new
end
p (Ender.new("q")..).first(3)
