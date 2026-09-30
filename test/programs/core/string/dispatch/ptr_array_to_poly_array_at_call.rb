# A method param that takes a mixed array, because one caller
# passes a heterogeneous literal `[A.new, "x"]`. Another caller
# passes a homogeneous `[A.new, A.new]`. Both calls must work, and
# the elements of the homogeneous array must stay A instances.

class A
  attr_reader :tag
  def initialize(t = "default"); @tag = t; end
end

def take(arr)
  arr.first
end

a_arr = [A.new("homogeneous"), A.new("entry2")]
mixed = [A.new("mixed_a"), "x"]
r1 = take(a_arr)
r2 = take(mixed)
# r1 should be an A instance.
# Verify by reading back the tag after a runtime is_a? check.
if r1.is_a?(A)
  puts r1.tag
else
  puts "NOT_A"
end
if r2.is_a?(A)
  puts r2.tag
else
  puts "NOT_A"
end
