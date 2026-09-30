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

path = "conv-target.txt"
begin
  # to_str at File path and mode slots (with and without a block)
  File.open(Stringish.new, Mode.new) { |f| f.write("hello\n") }
  p File.read(Stringish.new)
  p File.readlines(Stringish.new)
  p File.exist?(Stringish.new)
  p File.file?(Stringish.new)

  # to_int at index and count slots
  p [10, 20, 30][Idx.new]
  p [10, 20, 30].take(Idx.new)
  p [10, 20, 30].first(Idx.new)
  p "abc".getbyte(Idx.new)

  # to_str at string-method argument slots
  p "hello world".include?(Mode.new.to_str)
  p "wow".delete(Mode.new)
  p "hello=world".partition(Mode.new.to_str + "orl")

  # A class defining neither conversion is CRuby's TypeError. Reached
  # through a poly slot, the class is known only at run time, so the
  # TypeError is a run-time one, worded as CRuby words it.
  inert = [1, Inert.new][1]
  begin
    File.read(inert)
  rescue TypeError => e
    p [e.class, e.message]
  end
  begin
    [10, 20, 30].take(inert)
  rescue TypeError => e
    p [e.class, e.message]
  end
ensure
  File.delete(path) if File.exist?(path)
end

