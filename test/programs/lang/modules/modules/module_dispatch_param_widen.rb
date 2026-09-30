# A module-dispatch call site (`Disp.adapter.method(args)`, where
# Disp.adapter can hold one of N candidate classes). The only caller
# passes a poly value, so the param of each candidate's class method
# widens to poly. The dispatch picks the class that the slot holds.

class A
  def self.update(id)
    id
  end
end

class B
  def self.update(id)
    id
  end
end

module Disp
  class << self
    attr_accessor :adapter
  end
end

class C
  def initialize
    @id = 0
  end
  def write_str(s); @id = s; end   # widens @id to poly
  def save
    Disp.adapter.update(@id)         # ternary-dispatched: poly arg
  end
end

if ARGV.length > 0
  Disp.adapter = A
else
  Disp.adapter = B
end

c = C.new
c.write_str("hi")
c.save                              # no output expected; just compile
puts "ok"
