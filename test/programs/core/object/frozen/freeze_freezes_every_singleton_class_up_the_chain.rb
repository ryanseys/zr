# Freezing an object freezes its singleton class, that class's own
# singleton class, and so on up the chain that exists, also when each one
# has a prepended module. A class's subclass freezes its own chain and
# leaves its superclass's alone (ruby #20319).
x = Object.new
xs = x.singleton_class
xxs = xs.singleton_class
xxxs = xxs.singleton_class
x.freeze
p [xs.frozen?, xxs.frozen?, xxxs.frozen?]

y = Object.new
ys = y.singleton_class
ys.prepend(Module.new)
yys = ys.singleton_class
yys.prepend(Module.new)
yyys = yys.singleton_class
yyys.prepend(Module.new)
y.freeze
p [ys.frozen?, yys.frozen?, yyys.frozen?]

c = Class.new
cs = c.singleton_class
ccs = cs.singleton_class
cccs = ccs.singleton_class
d = Class.new(c)
ds = d.singleton_class
dds = ds.singleton_class
ddds = dds.singleton_class
d.freeze
p [d.frozen?, ds.frozen?, dds.frozen?, ddds.frozen?]
p [c.frozen?, cs.frozen?, ccs.frozen?, cccs.frozen?]
c.freeze
p [cs.frozen?, ccs.frozen?, cccs.frozen?]

# A singleton class made after the freeze is frozen too, and so is its own.
z = Object.new.freeze
p [z.singleton_class.frozen?, z.singleton_class.singleton_class.frozen?]
begin
  xxs.define_method(:m) {}
rescue => e
  p [e.class, e.message.sub(/0x\h+/, "0x")]
end

# Freezing a singleton class alone leaves its object unfrozen.
w = Object.new
ws = w.singleton_class
wss = ws.singleton_class
ws.freeze
p [w.frozen?, ws.frozen?, wss.frozen?]
