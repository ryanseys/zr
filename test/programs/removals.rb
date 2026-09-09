# remove_method, private_constant, subclasses,
# remove_instance_variable and caller.
class Base
  def greet = "base"
  def self.method_removed(name) = puts("removed #{name}")
end

class Kid < Base
  def greet = "kid"
end

k = Kid.new
p k.greet
Kid.send(:remove_method, :greet)
p k.greet
p Kid.instance_methods(false)
begin
  Kid.send(:remove_method, :greet)
rescue NameError => e
  puts e.message
  p e.name, e.receiver
end
class Kid
  def greet = "again"
  remove_method "greet"
end
p k.greet

module Conf
  SECRET = 1
  OPEN = 2
  private_constant :SECRET
  def self.peek = SECRET
end
p Conf::OPEN, Conf.peek, Conf.constants.sort, Conf.const_defined?(:SECRET), defined?(Conf::SECRET), defined?(Conf::OPEN)
begin
  Conf::SECRET
rescue NameError => e
  puts e.message
  p e.name
end
begin
  Conf.const_get(:SECRET)
rescue NameError => e
  puts e.message
end
begin
  Conf.send(:private_constant, :NOPE)
rescue NameError => e
  puts e.message
end
Conf.send(:public_constant, :SECRET)
p Conf::SECRET

class A; end
class B < A; end
class C < A; end
class D < B; end
p A.subclasses, B.subclasses, D.subclasses, Integer.subclasses, Class.new(A).superclass
o = Object.new
def o.x = 1
p A.subclasses.map(&:name)

class Bag
  def initialize
    @a = 1
    @b = 2
  end
end
b = Bag.new
p b.remove_instance_variable(:@a), b.instance_variables, b.remove_instance_variable("@b"), b.instance_variables
begin
  b.remove_instance_variable(:@zz)
rescue NameError => e
  puts e.message
  p e.name
end
begin
  b.remove_instance_variable(:zz)
rescue NameError => e
  puts e.message
end
begin
  b.freeze.remove_instance_variable(:@a)
rescue => e
  puts e.class
end

def inner = caller
def outer = inner
p outer
def inner0 = caller(0)
p inner0
def limited = caller(1, 1)
def limited_outer = limited
p limited_outer
p caller, caller(0).size, caller(5), caller(0, 0)
[1].each { p caller(0) }
begin
  caller(-1)
rescue ArgumentError => e
  puts e.message
end
begin
  caller(0, -1)
rescue ArgumentError => e
  puts e.message
end
