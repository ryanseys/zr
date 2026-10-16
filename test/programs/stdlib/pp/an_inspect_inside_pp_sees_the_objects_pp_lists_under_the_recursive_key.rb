require "pp"

# pp lists the objects it prints in Thread.current[:__recursive_key__],
# where the core's recursion guards (rb_exec_recursive) look too: an
# Array#inspect that an object's own inspect calls inside pp prints the
# Array that pp is printing as [...].
class HasInspect
  def initialize(a) = @a = a
  def inspect = "<inspect:#{@a.inspect}>"
end

class HasPrettyPrint
  def initialize(a) = @a = a

  def pretty_print(q)
    q.text "<pretty_print:"
    q.pp @a
    q.text ">"
  end
end

a = []
a << HasInspect.new(a)
puts PP.pp(a, +"")
puts a.inspect

b = []
b << HasPrettyPrint.new(b)
puts PP.pp(b, +"")

h = {}
h[:self] = HasInspect.new(h)
puts PP.pp(h, +"")
puts a.pretty_inspect

# The program's own list counts for each guarded method.
listed = [1, 2]
Thread.current[:__recursive_key__] = { inspect: { listed => true }.compare_by_identity }.compare_by_identity
puts listed.inspect, [listed].inspect, [1, 2].inspect
Thread.current[:__recursive_key__] = nil
puts listed.inspect

# The guards' Hash is not one of the thread's locals.
p Thread.current.key?(:__recursive_key__), Thread.current.keys.include?(:__recursive_key__)
Thread.current[:__recursive_key__] = { inspect: {}.compare_by_identity }.compare_by_identity
p Thread.current.key?(:__recursive_key__), Thread.current[:__recursive_key__].class
Thread.current[:__recursive_key__] = nil

# Each fiber has its own.
p Fiber.new { Thread.current[:__recursive_key__].nil? }.resume
