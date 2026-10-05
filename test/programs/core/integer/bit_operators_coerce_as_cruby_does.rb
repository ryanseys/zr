# A bit operator with an operand that is not an Integer calls coerce,
# then the operator of the first of the pair, whatever its class.
module ToSelf
  def coerce(other) = [self.class.new(other), self]
end

box = Struct.new(:value) do
  include ToSelf
  def &(other) = value & other.value
  def |(other) = value | other.value
  def ^(other) = value ^ other.value
end

p 3 & box.new(10)
p 3 | box.new(10)
p 3 ^ box.new(10)
p (2**70) & box.new(2**70 + 1)

def show
  p yield
rescue => e
  p [e.class, e.message]
end

show { 3 & 1.5 }
show { 3 | Object.new }
Plain = Struct.new(:value) { include ToSelf }
show { 3 ^ Plain.new(1) }
