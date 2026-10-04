# Struct, Data, Hash and ENV: names, keyword_init, inspect and pairs that
# convert with to_ary, as CRuby gives them.
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
show(1) { Struct.new(:a, keyword_init: 1).keyword_init? }
n = Object.new; def n.to_str = "Probe"
show(2) { Struct.new(n, :a).name }
class MyStruct < Struct; end
show(3) { MyStruct.new("Sub", :a).name }
K = Struct.new(:a, :b, keyword_init: true)
show(4) { K.new({ a: 1, b: 2 }) }
S = Struct.new(:a)
r1 = S.new; r1.a = r1
r2 = S.new; r2.a = r2
show(5) { r1.hash == r2.hash }
show(6) { x = S.new(1); y = S.new(x); y.a.a = y; z = S.new(S.new(z)); r1.eql?(S.new(2)) }
m = Module.new
m.const_set(:D, Data.define(:x))
show(7) { m::D.new(x: 1).inspect.sub(/0x\h+/, "X") }
c = Class.new
c.const_set(:D, Data.define(:x))
show(8) { c::D.new(x: 1).to_s.sub(/0x\h+/, "X") }
dn = Data.define(:x) do
  def self.name = "Custom"
end
show(9) { dn.new(x: 1).inspect }
DD = Data.define(:x) do
  def self.new(*) = raise("no new")
end
show(10) { DD.allocate.send(:initialize, x: 1) rescue $!; d = Data.define(:x).new(x: 1); d.with(x: 2) }
show(11) { ar = Object.new; def ar.to_ary = [[1, 2]]; Hash[ar] }
h1 = {}; h1[:a] = h1
h2 = {}; h2[:a] = h2
show(12) { h1.hash == h2.hash }
show(13) { a1 = [{}]; a1[0][:x] = a1; a2 = [{}]; a2[0][:x] = a2; a1.hash == a2.hash }
pr = Object.new; def pr.to_ary = [:k, :v]
show(14) { {a: 1}.to_h { pr } }
show(16) { ENV.to_h { pr } }
show(17) { e = ENV.select; e.class }
show(18) { ENV.filter.each { |k, v| k == "HOME" }.keys }
