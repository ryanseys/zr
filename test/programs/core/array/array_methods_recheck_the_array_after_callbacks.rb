# Array methods that call back into the program read the Array again
# afterwards, as CRuby's do.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

L = 2**63 - 1
show { [0][L..-1] = 2 }
show { [0][2**61..] = 2 }

x = Struct.new(:ary).new
def x.to_str
  ary[2] = [0, 1, 2]
  "z"
end
x.ary = ["a", "b", "c", x]
show { x.ary.join("") }

y = Struct.new(:ary).new
def y.to_str
  ary.clear
  ary[0] = "b"
  "z"
end
y.ary = Array.new(30) { "a" } << y
show { y.ary.join("") }

a = Object.new
def a.to_ary = [self]
show { [a].join }
show { [1, [2, [3, 4], 5]].join }

fa = [1, 2].freeze
show { fa.replace(42) }
show { [1].replace(42) }

ary = [1, 2, 3, 4, 5]
show { ary.sort! { |i, j| ary.freeze if i == 3; j <=> i } }
show { ary }

gen = Object.new
def gen.rand(n) = (@a.replace([]); 0.5)
def gen.with(a) = (@a = a; self)
show { (0...100).to_a.shuffle!(random: gen.with([])) }
big = (0...100).to_a
show { big.shuffle!(random: gen.with(big)) }
s = (0...100).to_a
show { s.sample(random: gen.with(s)) }
s = (0...100).to_a
show { s.sample(1, random: gen.with(s)) }

fmt = "c" * 100
o = Object.new
o.define_singleton_method(:to_int) { fmt.replace(""); 1 }
show { [o].pack(fmt) }

show { [].to_enum.first(L) }
