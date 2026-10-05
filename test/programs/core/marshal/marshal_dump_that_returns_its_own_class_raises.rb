# A marshal_dump that returns an instance of its own class would dump
# itself again without end, so Marshal refuses it.
class Copier
  def marshal_dump = dup
end

class Wrapper
  def initialize(n) = @n = n
  def marshal_dump = [@n]
  def marshal_load(a) = @n = a[0]
  attr_reader :n
end

begin
  Marshal.dump(Copier.new)
rescue RuntimeError => e
  p [e.class, e.message]
end
p Marshal.load(Marshal.dump(Wrapper.new(3))).n
