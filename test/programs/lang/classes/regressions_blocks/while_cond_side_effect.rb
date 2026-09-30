# `while (n = gets.to_i) > 0` runs the call in the predicate on each
# iteration, so each iteration reads a new line.
#
# The test uses an instance method that returns a String, then
# calls `.to_i`. The test cannot give input to stdin `gets`, so an
# iterator class takes its place.

class T_while_cond_side_effect_Source
  def initialize
    @data = ["5", "4", "3", "0"]
    @idx = 0
  end

  def next_line
    s = @data[@idx]
    @idx += 1
    s
  end
end

src = T_while_cond_side_effect_Source.new
count = 0
while (n = src.next_line.to_i) > 0
  count += 1
end
puts count
