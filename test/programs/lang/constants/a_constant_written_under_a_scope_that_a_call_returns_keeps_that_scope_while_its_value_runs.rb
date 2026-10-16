# `m::Z = v`: the scope is the value of a call. It stays alive while the
# value runs, a collection included, in a block as at the top.
def fresh = Module.new
def with(arg) = Module.new { const_set(:ARG, arg) }

m = 1.then { (k = fresh)::Z = 3; k }
p m::Z
p(1.then { fresh::Z = 4 })
p([1, 2].map { |i| with(i)::Y = i * 10 })

made = []
3.times do |i|
  scope = fresh
  made << scope
  scope.const_set(:I, i)
  (made.last)::V = (GC.start; Array.new(1000) { _1.to_s }.size + i)
end
p made.map { [_1::I, _1::V] }

holder = Struct.new(:mod).new(Module.new)
1.then { holder.mod::Q = Array.new(3) { GC.start; _1 } }
p holder.mod::Q

# An expression scope that is not a module fails as ruby's does.
begin
  1.then { 5::A = 1 }
rescue TypeError => e
  p [e.class, e.message]
end
begin
  1.then { nil.then { _1 }::A = 1 }
rescue TypeError => e
  p [e.class, e.message]
end

# The order: the scope runs before the value.
order = []
1.then { (order << :scope; fresh)::O = (order << :value; 1) }
p order
