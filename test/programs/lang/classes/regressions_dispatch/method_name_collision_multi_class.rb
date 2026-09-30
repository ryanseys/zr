# Multiple unrelated classes define the same method name. A call on
# each element of an Array of mixed objects calls each object's own
# method with the String arguments.
#
# Coverage:
#   - Two unrelated classes (Index/T_method_name_collision_multi_class_UsersHandler) define
#     `handle(req, res)` -- both get the Strings "/" and "ok".
#   - A third class (T_method_name_collision_multi_class_SQLite) has `attr_accessor :handle` (a
#     0-param getter). It takes no arguments, so the 2-arg call does
#     not go to it.
#   - `db.handle` (0-arg call) on the T_method_name_collision_multi_class_SQLite returns the ivar value
#     unchanged.

class T_method_name_collision_multi_class_IndexHandler
  def handle(req, res); "i-" + req + ":" + res; end
end
class T_method_name_collision_multi_class_UsersHandler
  def handle(req, res); "u-" + req + ":" + res; end
end
class T_method_name_collision_multi_class_SQLite
  attr_accessor :handle
  def initialize(name); @handle = name; end
end

handlers = [T_method_name_collision_multi_class_IndexHandler.new, T_method_name_collision_multi_class_UsersHandler.new]
i = 0
while i < handlers.length
  h = handlers[i]
  puts h.handle("/", "ok")
  i += 1
end

db = T_method_name_collision_multi_class_SQLite.new("conn-1")
puts db.handle
