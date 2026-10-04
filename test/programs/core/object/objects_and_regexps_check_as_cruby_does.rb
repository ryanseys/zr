# ObjectSpace, Regexp, Time, MatchData, Binding, Fiber, Mutex, Comparable
# and Class: argument checks and warnings as CRuby gives them.
$stderr = $stdout
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
Warning[:deprecated] = true
show(1) { ObjectSpace._id2ref(nil.object_id) }
show(2) { ObjectSpace::WeakMap.new.each_key.class }
show(3) { ObjectSpace::WeakMap.new.each.class }
show(4) { ObjectSpace::WeakMap.new.each_value.class }
show(5) { ObjectSpace::WeakMap.new.each_pair.class }
show(6) { m = ObjectSpace::WeakMap.new; k = +"a"; m[k] = 1; m.each_key }
k1 = Class.new { def hash = 1; def eql?(o) = true }
show(7) { m = ObjectSpace::WeakKeyMap.new; a = k1.new; m[a] = 1; m[k1.new] }
show(8) { ObjectSpace::WeakKeyMap.new[BasicObject.new] = 1 }
st = Object.new; def st.to_str = "abc"
show(9) { /abc/ === st }
show(10) { Regexp.new("a", Object.new) }
show(11) { Regexp.new(st) }
bad = Object.new; def bad.to_str = 1
show(12) { Regexp.new(bad) }
show(13) { /a/.hash == /a/n.hash }
show(14) { Regexp.linear_time?(/a/, "i") }
show(15) { Time.at(0).deconstruct_keys(1) }
show(16) { b = binding; x = 1; n = Object.new; def n.to_str = "x"; [b.local_variable_defined?(n), b.local_variable_set(n, 5), x] }
show(17) { Fiber["key"] = 1; Fiber["key"] }
fk = Object.new; def fk.to_str = "fkey"
show(18) { Fiber[fk] = 2; Fiber[:fkey] }
show(19) { /(?<a>.)/.match("x").deconstruct_keys(1) }
show(20) { Mutex.new.sleep(-1) }
cmp = Class.new { include Comparable; def <=>(o) = "x" }
show(21) { cmp.new == cmp.new }
show(22) { BasicObject.dup }
sd = Object.new; def sd.to_int = 5
show(23) { Random.new(sd).seed }
pr = Class.new { protected def pro = 1 }
show(24) { :pro.to_proc.call(pr.new) rescue $!.class }
show(25) { [(Mutex.new.sleep(0.001) rescue $!)].map(&:class) }
