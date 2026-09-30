class A1
  def method_missing(name, *args) = "mm:#{name}#{args}"
  def respond_to_missing?(*) = true
end
class B1 < A1
  def size = super + "!"
  def other(x) = super(x)
end
p B1.new.size, B1.new.other(1)
require "delegate"
class D1 < SimpleDelegator
  def size = super + 1
end
p D1.new([1, 2]).size
