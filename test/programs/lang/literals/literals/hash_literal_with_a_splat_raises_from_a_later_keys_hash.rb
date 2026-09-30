# A hash literal that carries `**` stores its other pairs one by one;
# a key whose `hash` raises must raise from the literal, not leave the
# literal with no value.
k = Object.new
def k.hash = raise("boom")
begin
  p({**{}, k => 1})
rescue => e
  p [e.class, e.message]
end
begin
  p({**{a: 1}, k => 1}.size)
rescue => e
  p [e.class, e.message]
end
p({**{a: 1}, b: 2})

