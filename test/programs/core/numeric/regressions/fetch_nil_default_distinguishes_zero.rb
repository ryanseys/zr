# hash.fetch(k, nil).nil? distinguishes missing-key from a 0 value.
h0 = {k: 0}
v0 = h0.fetch(:k, nil)
puts v0.nil? ? "missing" : "found-0"

hm = {}
vm = hm.fetch(:k, nil)
puts vm.nil? ? "missing" : "found-m"

h1 = {k: 42}
v1 = h1.fetch(:k, nil)
puts v1.nil? ? "missing" : "found-#{v1}"

hs = {"a" => 0}
vs = hs.fetch("a", nil)
puts vs.nil? ? "missing-str" : "found-str-#{vs}"

hsm = {}
vsm = hsm.fetch("a", nil)
puts vsm.nil? ? "missing-str-key" : "found-str-bad"
