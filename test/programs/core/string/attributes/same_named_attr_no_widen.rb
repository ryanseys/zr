# A receiver's attr_reader keeps the type of its own ivar, also when an
# unrelated class has an attr with the same name.
class Bag
  attr_accessor :payload
  def initialize; @payload = {"k" => "v"}; end
end

class Wire
  attr_accessor :payload
  def initialize; @payload = ""; end
end

def first_byte_of(s)
  s.bytes[0]
end

def handle_wire(w)
  first_byte_of(w.payload)
end

_b = Bag.new
_w = Wire.new
_w.payload = "hello"
puts handle_wire(_w)
