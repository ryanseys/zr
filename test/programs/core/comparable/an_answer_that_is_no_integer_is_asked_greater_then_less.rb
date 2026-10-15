# Comparable reads a `<=>` answer that is no Integer as rb_cmpint does: it
# asks `> 0`, then `< 0`, and the answer's own error names the operator it
# asked first.
class Answer
  def initialize(sign) = @sign = sign
  def >(other) = (print ">"; @sign == 1)
  def <(other) = (print "<"; @sign == -1)
end

class Box
  include Comparable
  def initialize(answer) = @answer = answer
  def <=>(other) = @answer
end

[1, -1, 0].each do |sign|
  box = Box.new(Answer.new(sign))
  results = [box < 1, box <= 1, box > 1, box >= 1, box.between?(0, 1), box.clamp(0, 1).class]
  puts " #{sign}: #{results.inspect}"
end
p Box.new(2**70) > 1, Box.new(-(2**70)) < 1, Box.new(0) >= 1
[false, "x", 1.5, nil].each do |answer|
  p Box.new(answer) < 1
rescue NoMethodError, ArgumentError => e
  p [e.class, e.message]
end
