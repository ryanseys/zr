# A ractor other than the main one: END raises IsolationError; finalizers
# on a class of the main ractor are refused both ways; it starts with no
# fiber storage of its creator's; a singleton class it gets reaches only a
# shareable attached object or one of its own. make_shareable freezes a
# Set's members, and a member whose freeze raises leaves the Set frozen
# but not shareable.
Warning[:experimental] = false
r = Ractor.new do
  END { nil }
rescue Ractor::IsolationError => e
  [e.class, e.message]
end
p r.value
p Ractor.new {
  res = []
  ObjectSpace.define_finalizer(Object.new, proc {}); res << :own_ok
  begin; ObjectSpace.define_finalizer(String, proc {}); res << :no; rescue Ractor::IsolationError => e; res << e.message; end
  begin; ObjectSpace.undefine_finalizer(String); res << :no; rescue Ractor::IsolationError => e; res << e.message; end
  res
}.value
Fiber[:key] = "creator"
p Ractor.new { Fiber[:key] }.value
o = Object.new
p Ractor.shareable?(o.singleton_class)
p Ractor.new(o.singleton_class) { |sc| begin; sc.attached_object; rescue Ractor::IsolationError => e; e.message.sub(/0x\h+/, ""); end }.value
sh = Ractor.make_shareable(Object.new)
p Ractor.new(sh.singleton_class) { |sc| sc.attached_object }.value.equal?(sh)
p Ractor.new(String.singleton_class) { |sc| sc.attached_object }.value
p Ractor.new { own = Object.new; own.singleton_class.attached_object.equal?(own) }.value
raiser = Class.new { def freeze = raise("boom") }
set = Set.new([raiser.new])
begin; Ractor.make_shareable(set); rescue => e; p e.message; end
p Ractor.shareable?(set), set.frozen?
s2 = Set[+"a", [+"b"]]
Ractor.make_shareable(s2)
p Ractor.shareable?(s2), s2.all?(&:frozen?), s2.to_a.last.first.frozen?
p Ractor.shareable?(Set[+"x"].freeze), Ractor.shareable?(Set[:x].freeze)
p Ractor.new { Fiber[:mine] = 1; Fiber.new { Fiber[:mine] }.resume }.value
