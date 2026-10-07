# A class's new instances get the room that its instances needed until
# now, as CRuby's max_iv_count gives them. Object and BasicObject never
# grow: a plain object with many instance variables, or the runtime's own
# state on ENV, leaves each Object.new at the smallest slot.
require "objspace"

base = ObjectSpace.memsize_of(Object.new)
p ObjectSpace.memsize_of(Object.new) == base

plain = Object.new
10.times { |i| plain.instance_variable_set("@iv_#{i}", i) }
p ObjectSpace.memsize_of(Object.new) == base
p ObjectSpace.memsize_of(plain) > base

ENV["ZR_PROBE"] = "1"
ENV.to_h
p ObjectSpace.memsize_of(Object.new) == base

bare = BasicObject.new
p ObjectSpace.memsize_of(bare) == base
p ObjectSpace.memsize_of(BasicObject.new) == base

class TestClass
end
p ObjectSpace.memsize_of(TestClass.new) == base

# A class of the program does learn: after one of its objects needed room
# for ten variables, its next objects start larger.
class Learner
end
learner = Learner.new
10.times { |i| learner.instance_variable_set("@iv_#{i}", i) }
p ObjectSpace.memsize_of(Learner.new) > base
GC.start
p ObjectSpace.memsize_of(Learner.new) > base

# A subclass of Object is not Object.
class Child < Object
  def fill = (@a = @b = @c = @d = @e = @f = 1)
end
Child.new.fill
p ObjectSpace.memsize_of(Child.new) > base
p ObjectSpace.memsize_of(Object.new) == base
