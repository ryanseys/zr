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

# The same protocol reached through a POLY slot, where the class is not known
# until run time: the container read hands the builtin a boxed object, which
# converts through the bridge. These answered a wrong result in SILENCE before
# -- #to_s's "#<Idx>" rendering for a String slot, 0 for an Integer one -- so
# the point of each line is that it now matches CRuby rather than raising.
boxed_str = [1, Stringish.new][1]
boxed_int = [1, Idx.new][1]
p "a conv-target.txt b".index(boxed_str)
p "a conv-target.txt b".include?(boxed_str)
p [10, 20, 30].first(boxed_int)
p [10, 20, 30][boxed_int]
p "abc".getbyte(boxed_int)
p "wow".delete([1, Mode.new][1])
p [boxed_int].pack("C").bytes

