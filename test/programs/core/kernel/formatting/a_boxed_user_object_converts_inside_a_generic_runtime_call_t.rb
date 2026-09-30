# CRuby's implicit conversion protocol at builtin argument boundaries: a user
# object defining #to_str / #to_int converts where a String / Integer is
# wanted; one that defines neither raises CRuby's TypeError.
class Stringish
  def to_str
    "conv-target.txt"
  end
end

class Mode
  def to_str
    "w"
  end
end

class Idx
  def to_int
    1
  end
end

class Inert
end

# the runtime bridge: a BOXED user object converts inside a generic runtime
# walk (pack), including a conversion method that arrives through a mixin
module IntLike
  def to_int
    7
  end
end

class Mixed
  include IntLike
end

p [Idx.new].pack("C").bytes
p [Mixed.new, Idx.new].pack("C2").bytes
begin
  [Inert.new].pack("C")
rescue TypeError => e
  p [e.class, e.message]
end
begin
  [nil].pack("C")
rescue TypeError => e
  p [e.class, e.message]
end
p [2**64 + 65].pack("Q")[0]

