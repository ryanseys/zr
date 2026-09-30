# An implicit conversion asks as rb_check_funcall does: a BasicObject
# converts, a method_missing answers unless it raises NoMethodError, and
# a nil result converts nothing.
b = BasicObject.new
def b.to_str = "b"
i = BasicObject.new
def i.to_int = 66
p [String.try_convert(b), format("%c%c", b, i), Integer.try_convert(i)]
m = Object.new
def m.method_missing(name, *) = name == :to_hash ? { a: 1 } : super
p [Hash.try_convert(m), String.try_convert(m)]
def splat(*a) = a
x = Object.new
x.singleton_class.define_method(:to_a) { nil }
y = Object.new
def y.method_missing(name, *) = name == :to_a ? [7, 8] : super
p [splat(*x).size, splat(*y)]
s = Object.new
class << s
  undef_method :to_s
  def method_missing(name, *) = name == :to_s ? "via missing" : super
end
p String(s)
t = Object.new
def t.to_s = 5
begin
  String(t)
rescue TypeError => e
  p e.message
end
