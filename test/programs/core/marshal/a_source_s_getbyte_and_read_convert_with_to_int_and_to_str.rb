# r_byte reads getbyte's value with NUM2CHR, and r_bytes read's with
# StringValue, so a source may give what converts.
class ToInt < BasicObject
  def initialize(v) = @v = v
  def to_int = @v
end
class ToStr < BasicObject
  def initialize(v) = @v = v
  def to_str = @v
end
src = Marshal.dump([1, "ab", :c, 2.5])
s = Struct.new(:bytes).new(src.chars)
def s.getbyte = (c = bytes.shift) && ToInt.new(c.ord)
def s.read(n) = ToStr.new(bytes.shift(n).join)
p Marshal.load(s)
s2 = Struct.new(:bytes).new(src.chars)
def s2.getbyte = bytes.shift
def s2.read(n) = bytes.shift(n).join
p Marshal.load(s2)
s3 = Struct.new(:bytes).new(src.chars)
def s3.getbyte = Object.new
def s3.read(n) = bytes.shift(n).join
p((Marshal.load(s3) rescue [$!.class, $!.message]))
