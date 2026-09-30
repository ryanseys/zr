# A call through a class-valued slot reaches the method of the class it
# holds, and each candidate has its own parameter list. A candidate with
# optional params gets their defaults. A class with no such method raises
# NoMethodError.
class Holder
  def initialize(k)
    @k = k
  end

  def klass
    @k
  end

  def go1
    klass.f(1)
  end

  def go2
    klass.g(1, 2)
  end
end

class A
  def self.f(x, y = nil)
    "A.f(#{x.inspect}, #{y.inspect})"
  end

  def self.g(x, r)
    "A.g"
  end
end

class B
  def self.f(x, y = nil)
    "B.f(#{x.inspect}, #{y.inspect})"
  end

  def self.g(x, r, extra = nil)
    "B.g(extra=#{extra.inspect})"
  end
end

puts Holder.new(A).go1
puts Holder.new(B).go1
puts Holder.new(A).go2
puts Holder.new(B).go2

class NoMethods
end

begin
  Holder.new(NoMethods).go1
  puts "no raise"
rescue NoMethodError
  puts "NoMethodError"
end
