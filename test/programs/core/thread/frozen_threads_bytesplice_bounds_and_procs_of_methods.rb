# Cases that once hung: a frozen thread's locals, bytesplice bounds, a
# Method's proc under instance_exec and instance_eval, pread of a negative
# size, and a BOM| pipe encoding.
Thread.new do
  th = Thread.current
  th.freeze
  p((th[:foo] = "bar") rescue $!)
end.join
p(("hello".bytesplice(2, 1, "HELLO", 6, 0) rescue $!), ("abc".bytesplice(0, 1, "", 0, -2) rescue $!))
p 3.instance_exec(4, &5.method(:+))
def meth(arg) = arg
obj = Object.new
p obj.instance_eval(&method(:meth)).equal?(obj)
File.open(__FILE__) { |f| p((f.pread(-4, 0) rescue $!)) }
IO.pipe("BOM|UTF-8:ISO-8859-1") { |rd, _| p rd.external_encoding, rd.internal_encoding }
