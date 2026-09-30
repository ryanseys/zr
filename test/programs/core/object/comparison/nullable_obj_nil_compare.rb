# `if c != nil` (or `while c != nil`) on a user-class local that
# can be nil checks the value at run time. The body does not run
# when c is nil. A route dispatch loop such as
# `while route != nil && !served` has this shape.
#
# Coverage:
#   - if c != nil / if c / if !c.nil? on a function returning
#     nil-or-Foo: all three forms agree.
#   - while c != nil on the same shape: loop terminates instead
#     of spinning forever.
#   - a local that is never nil (c = Foo.new) answers TRUE for
#     != nil.

class Box
  attr_accessor :tag
  def initialize(tag)
    @tag = tag
  end
end

def find_or_nil(want)
  if want == "yes"
    return Box.new("found")
  end
  nil
end

# 1. nil branch -- all three forms should agree.
c = find_or_nil("no")
puts "c=" + (c.nil? ? "nil" : "non-nil")     # c=nil

if c != nil
  puts "ne-nil: ENTERED"
else
  puts "ne-nil: skipped"                      # skipped (correct)
end

if c
  puts "tr: ENTERED"
else
  puts "tr: skipped"                          # skipped
end

if !c.nil?
  puts "not-nilq: ENTERED"
else
  puts "not-nilq: skipped"                    # skipped
end

# 2. non-nil branch -- all three forms enter the body.
d = find_or_nil("yes")
puts "d=" + (d.nil? ? "nil" : "non-nil")     # d=non-nil

if d != nil
  puts "d-ne-nil: ENTERED"                    # ENTERED
else
  puts "d-ne-nil: skipped"
end

# 3. while loop terminates instead of spinning.
n = 0
while c != nil
  n += 1
  break if n > 3
end
puts "n=" + n.to_s                            # n=0

# 4. non-nullable obj (Foo.new is always non-nil) still folds.
e = Box.new("eager")
if e != nil
  puts "e-ne-nil: ENTERED"                    # ENTERED (non-nullable, always true)
else
  puts "e-ne-nil: skipped"
end
