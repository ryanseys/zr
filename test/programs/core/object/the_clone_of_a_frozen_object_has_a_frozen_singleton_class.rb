# The clone of a frozen object, class or module is frozen, and so is the
# singleton class that it took from the original (rb_obj_freeze_inline):
# a singleton method on it raises FrozenError. A dup and a
# clone(freeze: false) are not frozen.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}"
end
t("class clone") { c = Class.new.freeze.clone; [c.frozen?, c.singleton_class.frozen?] }
t("class clone ivar") { c = Class.new.freeze.clone; c.instance_variable_set(:@a, 1) }
t("class clone sdef") { c = Class.new.freeze.clone; def c.x; end }
t("module clone") { m = Module.new.freeze.clone; [m.frozen?, m.singleton_class.frozen?] }
t("module clone sdef") { m = Module.new.freeze.clone; m.define_singleton_method(:x) {} }
t("obj clone") { o = Object.new.freeze.clone; [o.frozen?, o.singleton_class.frozen?] }
t("obj clone singleton made") { o = Object.new; o.singleton_class; o.freeze; c = o.clone; [c.frozen?, c.singleton_class.frozen?] }
t("str clone") { s = "a".dup.freeze.clone; [s.frozen?, s.singleton_class.frozen?] }
t("class clone true") { c = Class.new.clone(freeze: true); [c.frozen?, c.singleton_class.frozen?] }
t("class frozen dup") { c = Class.new.freeze.dup; [c.frozen?, c.singleton_class.frozen?] }
t("class clone false") { c = Class.new.freeze.clone(freeze: false); [c.frozen?, c.singleton_class.frozen?] }
t("singleton of frozen") { k = Class.new.freeze; [k.singleton_class.frozen?, k.singleton_class.singleton_class.frozen?] }
t("ext obj clone") { o = Object.new.extend(Comparable).freeze; c = o.clone; [c.frozen?, c.singleton_class.frozen?, c.is_a?(Comparable)] }
t("ext obj clone sdef") { o = Object.new; def o.x = 1; o.freeze; c = o.clone; [c.x, (def c.y; end rescue $!.class)] }
t("class clone ancestors") { k = Class.new { def self.hi = :hi }.freeze; c = k.clone; [c.hi, c.singleton_class.frozen?] }
t("class clone thawed singleton") { k = Class.new.freeze; c = k.clone(freeze: false); def c.z = :z; c.z }
