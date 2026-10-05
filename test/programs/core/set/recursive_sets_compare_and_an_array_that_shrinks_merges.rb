# Sets that contain themselves compare equal and hash the same, and a
# merge of an Array that an element's hash empties stops at its new end.
set1 = Class.new(Set)["a", "b"]
set1.add(set1).reset
set2 = Set["a", "b", Set["a", "b", set1]]
p set1 == set2, set2 == set1, set1.hash == set2.hash
a = (1..100).to_a
o = Object.new
o.define_singleton_method(:hash) do
  a.clear
  0
end
a.unshift o
p Set.new.merge(a).to_a.size
b = (1..100).to_a
o2 = Object.new
o2.define_singleton_method(:hash) { b.clear; 0 }
b.unshift o2
p Set.new(b).to_a.size
s = Set[1]
s << s
s.reset
p s.hash == Set[1, s].hash, s.hash == Set[1, Set[1, s]].hash, s == Set[1, Set[1, s]]
p Set[1, 2].hash == Set[2, 1].hash, Set[[1]].hash == Set[[1]].hash
