# A constant whose name is in another encoding than UTF-8: it is set,
# read, defined? and removed, and the NameError for it has a message in
# the name's encoding.
names = [*%W"\u{00de} \u{00C0}".flat_map { |c| [c, c.encode("iso-8859-15")] }, "\u{1c4}", "\u{1f2}", "\u{1f88}", "\u{370}",
         *%W"\u{391} \u{ff21}".flat_map { |c| [c, c.encode("cp932"), c.encode("euc-jp")] }]
names.each do |n|
  m = Module.new
  r = [n.encoding.name, m.const_defined?(n), (m.const_get(n) rescue $!.class), eval("defined?(m::#{n})")]
  m.const_set(n, 42)
  r += [m.const_defined?(n), eval("defined?(m::#{n})"), m.const_get(n), m.constants.map(&:encoding).map(&:name)]
  m.__send__(:remove_const, n)
  r += [m.const_defined?(n), eval("defined?(m::#{n})")]
  k = Module.new
  c = k.module_eval("class #{n}; self; end")
  r += [k.const_get(n).equal?(c), c.name.encoding.name]
  p r
rescue Exception => e
  p [n.encoding.name, :error, e.class, e.message[0, 70]]
end
names.each do |n|
  m = Module.new
  e = (m.const_get(n) rescue $!)
  msg = e.message
  p [n.encoding.name, msg.encoding.name, msg.valid_encoding?, (msg =~ /uninitialized/), msg.sub(/0x\h+/, "X").b]
rescue Exception => x
  p [n.encoding.name, :error, x.class, x.message[0, 90]]
end
n = "\u{391}".encode("euc-jp")
e = (eval("#{n}") rescue $!)
p [e.class, e.message.encoding.name, e.message.valid_encoding?, e.name.encoding.name]
