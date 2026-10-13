# A dup or clone of a class from Class.allocate is not initialized: it
# cannot make instances until its own `initialize` gives it a superclass,
# and it then allocates as that superclass does (rb_mod_init_copy).
[-> { Class.allocate.dup.new }, -> { Class.allocate.clone.new }, -> { Class.allocate.new },
 -> { c = Class.allocate; c.singleton_class; c.dup.new },
 -> { Class.allocate.dup.superclass }, -> { Class.allocate.dup.allocate },
 -> { d = Class.allocate.dup; d.send(:initialize); d.new.class == d },
 -> { Class.new.dup.new.class.class },
 -> { c = Class.allocate; c.send(:initialize); [c.superclass, c.new.class == c] },
 -> { c = Class.allocate; c.send(:initialize, Array); [c.superclass, c.new.class == c, c.new.to_a] },
 -> { c = Class.allocate.dup; c.send(:initialize, String); [c.superclass, c.new("x"), c.new("y").class == c] },
 -> { c = Class.allocate.clone; c.send(:initialize, Hash); c.new.merge(a: 1) },
 -> { c = Class.allocate.dup; c.send(:initialize, Integer); c.new },
 -> { c = Class.allocate.dup; c.send(:initialize); c.send(:initialize) },
 -> { c = Class.allocate.dup.dup; c.send(:initialize, Array) { def hi = size }; c.new([1, 2]).hi },
 -> { Class.new(String).dup.new("s") + "t" },
 -> { c = Class.allocate; c.send(:initialize) { def hi = 1 }; c.new.hi }].each do |f|
  p f.call
rescue => e
  p [e.class, e.message.sub(/0x\h+/, "XX")]
end
