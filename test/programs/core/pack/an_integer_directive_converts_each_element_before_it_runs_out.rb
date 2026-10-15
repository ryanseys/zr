# Array#pack converts the elements of an integer directive one at a time,
# so a bad element raises TypeError before a count past the end raises
# "too few arguments"; good elements before the end are packed first.
def try(items, template)
  p [template, items.pack(template)]
rescue => e
  p [template, e.class, e.message]
end

try([nil], "C2")
try([1], "C2")
try([1, nil], "C3")
try([:a], "n2")
try([nil], "q2")
try([nil], "j2")
try([2**70], "C2")
try([1, 2], "S3")
try([1, 2, 3], "S3")
try([1, "2"], "l2")
try([1.5, 2.5], "C2")
try([], "N")
try([nil], "s*")
try([1, 2], "C*C")
class Shrinker
  def initialize(list) = @list = list
  def to_int
    @list.pop
    7
  end
end
list = [0, nil, 9]
list[1] = Shrinker.new(list)
try(list, "C3")
