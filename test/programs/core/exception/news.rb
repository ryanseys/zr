# Which `new` calls leave a `Class#new` row in a backtrace.
class Foo
  def initialize(*args, **opts)
    raise "x"
  end

  def self.make = new
  def self.make_self = self.new
end

class Bar
  private_class_method :new

  def initialize
    raise "y"
  end

  def self.make = new
end

def report
  yield
rescue => e
  puts e.backtrace
end

report { Foo.new }
report { Foo.new(1, 2) }
report { Foo.new(a: 1) }
report { Foo.new(*[1]) }
report { Foo.new(**{}) }
report { Foo.make }
report { Foo.make_self }
report { Foo.new { } }
report { Foo.new(&nil) }
report { Foo.send(:new) }
report { Foo.__send__(:new) }
report { Foo.method(:new).call }
report { Class.new { raise "z" } }
report { Bar.make }
report { Bar.new }
report { Foo&.new }
