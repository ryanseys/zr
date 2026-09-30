# `obj.attr ||= v` and `&&=` call the reader and, conditionally, the writer.
# A hand-written writer runs, like for `attr = v` and `attr += v`. This is
# true whether or not an ivar has the same name as the method.
$log = []

class Box
  def initialize
    @v = nil
  end

  def v
    $log << :read
    @v
  end

  def v=(value)
    $log << :write
    @v = value * 10
  end
end

b = Box.new
p (b.v ||= 7)          # assigns: the value is what was ASSIGNED, not the
p b.v                  # writer's return and not a re-read
p $log

# Assigning again finds it truthy: reader once, no writer, no right-hand side.
$log = []
$evaluated = 0
def side
  $evaluated += 1
  9
end
p (b.v ||= side)
p [$log, $evaluated]

# `&&=` is the mirror, including the value on the arm that does not assign.
$log = []
c = Box.new
p (c.v &&= 7)
p [c.v, $log]
c2 = Box.new
c2.v = 1
$log = []
p (c2.v &&= 7)
p [c2.v, $log]

# The ivar need not share the method's name -- this was the shape that failed
# to build rather than failing silently.
class Session
  def initialize = @raw = nil
  def last_active_at = @raw
  def last_active_at=(value)
    $log << :sw
    @raw = value
  end
  def touch = self.last_active_at ||= 7
end
$log = []
s = Session.new
p s.touch
p [s.last_active_at, $log]

# A receiver that is not `self`, in statement position, evaluated ONCE.
$n = 0
def recv(x)
  $n += 1
  x
end
d = Box.new
recv(d).v ||= 5
p [d.v, $n]

# A generated accessor keeps the direct path and the same answers.
class Plain
  attr_accessor :a
end
q = Plain.new
p (q.a ||= 3)
p (q.a ||= 4)
p q.a
