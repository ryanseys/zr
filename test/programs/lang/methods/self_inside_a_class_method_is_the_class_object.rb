# A class method's `self` is the class object, so `self` and the
# class constant are interchangeable -- including as a receiver for
# the class's OWN other class methods.

class Foo
  def self.bar
    self
  end
  def self.baz
    self.bar.name
  end
end
p Foo.bar
p Foo.bar == Foo
p Foo.baz
p Foo.bar.new.class
