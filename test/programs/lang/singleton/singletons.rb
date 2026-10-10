class Foo
  def self.bar
    yield
  end
  class << self
    def baz = bar { raise "x" }
    attr_accessor :count
  end
end
o = Object.new
def o.hi
  raise "hi"
end
begin
  Foo.baz
rescue => e
  puts e.backtrace
end
begin
  o.hi
rescue => e
  puts e.backtrace
end
p Foo.singleton_class, o.singleton_class, Foo.singleton_class.superclass, Foo.singleton_class.singleton_class
p Foo.class, o.class, Foo.singleton_class.class
class Sub < Foo; end
p Sub.baz rescue p $!
Foo.count = 3
p Foo.count, Sub.count
p Sub.singleton_class.superclass
def Foo.each; end


class << o
  raise "in sclass"
end
