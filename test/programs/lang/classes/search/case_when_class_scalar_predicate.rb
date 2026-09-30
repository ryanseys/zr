# `case <scalar> when ClassConst` on a String, an Integer and a
# Symbol. The arm uses Module#===, so it matches only when the
# class corresponds to the kind of the value (Integer / Float for
# numeric, String for string, Symbol for symbol, TrueClass /
# FalseClass for bool). Any other class does not match.

class Box
  attr_accessor :v
  def initialize; @v = nil; end
  def setstr(s); @v = s; end
end

def classify(b)
  v = b.v
  case v
  when String
    "string"
  else
    "other"
  end
end

b1 = Box.new
b1.setstr("hello")
puts classify(b1)

# int predicate + class consts
n = 42
case n
when Integer
  puts "int-matched"
when String
  puts "wrong"
else
  puts "no"
end

# sym predicate + class consts
s = :hello
case s
when Symbol
  puts "sym-matched"
when String
  puts "wrong-sym"
else
  puts "no-sym"
end
