# ruby labels the frame of a method that an alias reached with the
# alias's owner when the method came from a class (rb_alias makes the
# alias's class the entry's owner): 'Klass.<=>', 'A#fetch', 'Bar#a'. An
# alias of a module's method keeps the module. FileTest's functions are
# File's (define_filetest_function), and its frame says
# 'FileTest.exist?'. Found by zr-dev fuzz.
def label
  yield
rescue StandardError => e
  p e.backtrace_locations.first.label
end

class Klass
  singleton_class.alias_method :nickname, :<=>
end
label { Klass.nickname }

class A < Array
  alias x fetch
end
label { A.new.x(9) }

class H < Hash
  alias_method :get, :fetch
end
label { H.new.get(:k) }

class B
  include Comparable
  alias_method :btw, :between?
end
label { B.new.btw }

class String
  alias_method :ss, :sub
end
label { "".ss }

label { FileTest.exist?(1) }
label { FileTest.directory?(nil) }
label { FileTest.size?(:a) }

def labels
  yield
rescue StandardError => e
  p e.backtrace_locations.first(2).map(&:label)
end

class Foo
  def a = raise("x")
end

class Bar < Foo
  alias c a
end
labels { Bar.new.c }
labels { Foo.new.a }

o = Object.new
o.singleton_class.alias_method(:ff, :instance_variable_get)
labels { o.ff(:bad) }

class W < Hash
  alias_method :g2, :fetch
end

class W2 < W
  alias_method :g3, :g2
end
labels { W2.new.g3(1) }
labels { W.new.g2(1) }
labels { W.new.fetch(1) }
labels { Class.new(Array) { alias_method :zz, :fetch }.new.zz(1) }

class Sub2 < Array; end
Sub2.alias_method :yy, :first
labels { Sub2.new.yy(-1) }
labels { Array.alias_method(:fetch2, :fetch); [].fetch2(1) }

module Mo
  def self.f = raise("m")
  module_function

  def g = raise("g")
end
labels { Mo.f }
labels { Mo.g }

class Deep < Foo
  alias c a
  def a = super
end
labels { Deep.new.c }
labels { Deep.new.a }

# The alias's owner is its class; it keeps the original's code.
p Bar.instance_method(:c).owner, Sub2.instance_method(:yy).owner, W2.instance_method(:g3).owner
p Bar.instance_method(:c).name, Bar.instance_method(:c).original_name
