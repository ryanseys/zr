# Marshal.load extends a user-marshaled object (U) with the modules of
# its `e` record before it calls marshal_load, so a module's methods,
# marshal_load too, are there; the payload does not take them. A load
# adds modules as rb_extend_object and rb_prepend_module do: the
# extend_object, extended, prepend_features and prepended hooks do not
# run (the hooks below print only for the program's own extend).
module Meths
  def meths_method = :m
  def self.extended(o) = puts("extended hook")
  def self.extend_object(o) = (puts("extend_object hook"); super)
end
module MethsMore; def more = :x; end
module Pre
  def self.prepended(c) = puts("prepended hook")
  def self.prepend_features(c) = (puts("prepend_features hook"); super)
end
class U
  def marshal_dump = :data
  def marshal_load(data) = (puts "in marshal_load: #{respond_to?(:meths_method)} #{singleton_class.ancestors[1, 2].inspect}")
end
class P
  attr_accessor :payload
  def initialize(p) = @payload = p
  def marshal_dump = @payload
  def marshal_load(d) = (@payload = d; puts "load: #{is_a?(Meths)} payload #{d.is_a?(Meths)} #{d.is_a?(MethsMore)}")
end
module Override
  def marshal_load(data) = (@via = :override; @data = data)
end
class V
  attr_reader :via, :data
  def marshal_dump = [1, 2]
end
o = Marshal.load("\x04\be:\nMethsU:\x06U:\tdata")
p o.is_a?(Meths)
o = Marshal.load("\x04\be:\nMethsU:\x06Po:\vObject\x00")
p [o.is_a?(Meths), o.payload.is_a?(Meths)]
o = Marshal.load("\x04\be:\nMethsU:\x06Pe:\x0EMethsMoreo:\vObject\x00")
p [o.is_a?(Meths), o.is_a?(MethsMore), o.payload.is_a?(Meths), o.payload.is_a?(MethsMore)]
# Two modules on one user-marshaled object, in the order extend gave.
x = U.new.extend(Meths).extend(MethsMore)
d = Marshal.dump(x)
p d
y = Marshal.load(d)
p y.singleton_class.ancestors[1, 3]
# A module that defines marshal_load is used for a class that has none.
v = Marshal.load("\x04\be:\rOverrideU:\x06V[\x07i\x06i\x07")
p [v.via, v.data]
# Plain objects, arrays and strings that were extended.
o = Marshal.load(Marshal.dump(Object.new.extend(Meths)))
p o.singleton_class.include?(Meths)
s = Marshal.load(Marshal.dump(+"str".extend(Meths)))
p [s, s.is_a?(Meths)]
a = Marshal.load(Marshal.dump([1, [2].extend(MethsMore)].extend(Meths)))
p [a.is_a?(Meths), a[1].is_a?(MethsMore), a[1].is_a?(Meths)]
# A prepended module on a singleton class.
q = Object.new
q.singleton_class.prepend(Pre)
d = Marshal.dump(q)
p d
r = Marshal.load(d)
p r.singleton_class.ancestors.first(2).map { |c| c.singleton_class? ? :singleton : c }
