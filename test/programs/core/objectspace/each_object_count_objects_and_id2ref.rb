# ObjectSpace walks the heap: each_object by class, the singleton classes a
# walk shows and hides as internal_object_p does, the census by type, and
# _id2ref for an id a program asked for.
class Shape; end
class Circle < Shape; end
class Square < Shape; end
o = Object.new
def o.x = 1
p ObjectSpace.each_object(Class).select { |k| k < Shape }.sort_by(&:name)
p ObjectSpace.each_object(Shape.singleton_class).to_a.sort_by(&:name)
p ObjectSpace.each_object(Class).any? { |k| k.singleton_class? && k.attached_object == o }
shapes = [Circle.new, Circle.new, Square.new]
p ObjectSpace.each_object(Circle).count
e = ObjectSpace.each_object(Shape)
p e.class, e.size
p ObjectSpace.each_object(Square) { |s| p s.class }
p ObjectSpace.count_objects.first(2).map(&:first)
counts = ObjectSpace.count_objects
p counts[:TOTAL] >= counts[:FREE] + counts[:T_STRING], counts.keys.include?(:T_ARRAY)
h = {}
p ObjectSpace.count_objects(h).equal?(h)
x = "hello"
p ObjectSpace._id2ref(x.object_id).equal?(x)
p ObjectSpace._id2ref(nil.object_id), ObjectSpace._id2ref(7.object_id), ObjectSpace._id2ref(true.object_id)
p((ObjectSpace._id2ref(1 << 40) rescue $!))
p((ObjectSpace._id2ref(:a) rescue $!))
p((ObjectSpace.each_object(3) rescue $!))
p shapes.size

