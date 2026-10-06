# Array#pack converts each item as CRuby's StringValue, rb_to_float and
# NUM2INT do, raises at an unknown directive in order, and packs into a
# buffer from its start, so `@` counts from there.
obj = Object.new
def obj.to_int = 1
def obj.to_str = "1"
def obj.to_f = 1.0
def obj.to_s = "1"
%w[a A Z B b H h u m M C c S s L l Q q J j N n V v U w D d F f E e G g P p x X @].each do |d|
  r = begin
    [obj, obj, obj, obj].pack("a \t\n\v\f\r" + d).bytesize
  rescue => e
    "#{e.class}: #{e.message}"
  end
  r2 = begin
    [obj, obj, obj, obj].pack("a R" + d)
  rescue => e
    "#{e.class}: #{e.message}"
  end
  p [d, r, r2]
end
n = [65, 66, 67]
[+"", +"123", +"12345", +"123456", +"1234567890"].each do |b|
  r = n.pack("ccc", buffer: b.dup)
  p [r, n.pack("@3ccc", buffer: b.dup), n.pack("@6ccc", buffer: b.dup)]
end
buf = +"x"
p n.pack("ccc", buffer: buf).equal?(buf)
iso = "".encode(Encoding::ISO_8859_1)
n.pack("ccc", buffer: iso)
p iso.encoding, iso
p ([65].pack("c", buffer: []) rescue [$!.class, $!.message])
p ([65].pack("c", buffer: "f".freeze) rescue $!.class)
o = Object.new
def o.to_str = "1"
p [o, o].pack("a\t\n# comment\nA2"), [1].pack("@"), [1, 2].pack("C@C")
p ([1].pack("a R") rescue $!.message)
class NoFloat < Numeric; end
k = NoFloat
p ([k.new].pack("d") rescue [$!.class, $!.message])
o = Object.new
def o.to_s = 2
p ([o].pack("M").start_with?("#<Object:0x") rescue [$!.class, $!.message])
o2 = Object.new
def o2.to_int = "5"
p ([o2].pack("U") rescue [$!.class, $!.message])
