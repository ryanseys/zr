S = Struct.new(:a, :b)
class Plain; def initialize; @x = 1; @y = "s"; end; end
class Dumped; def _dump(l) = "ud"; def self._load(s) = new; end
class Marshalled; def marshal_dump = [1, 2]; def marshal_load(a) = @a = a; end
class MyStr < String; end
module Ext; end

def wire(x) = Marshal.dump(x).bytes.join(",")

shared = [1]
sstr = "x"
[nil, true, false, 0, 1, 122, 123, 255, 256, -1, -123, -124, 2**30, 2**30 - 1, -(2**30), -(2**30) - 1,
 2**40, -(2**40), 2**70, 1.0, -0.0, 0.0, 1.5, 1e100, 1e-100, 1e-5, 0.0001, 100.0, 0.5, -1.25e-7,
 Float::INFINITY, -Float::INFINITY, 3.14159265358979, 123456.0, 1234560.0, 5e-324,
 :sym, :"a b", "str", "stér", "bin".b, "a".dup.force_encoding("US-ASCII"),
 (1..2), (1...2), (1..), /ab/ix, //n, S.new(1, "x"), Plain.new, Dumped.new, Marshalled.new, MyStr.new("q"),
 [1, [2]], {1 => 2}, Hash.new(0), String, Comparable, Rational(3, 4), Complex(0, 2),
 [shared, shared], [sstr, sstr, :a, :a], Object.new.tap { |o| o.extend(Ext) },
 { a: 1 }.tap { |h| h.instance_variable_set(:@z, 3) },
 [1, 2, 3].tap { |a| a.instance_variable_set(:@q, :r) }].each do |value|
  puts wire(value)
end

p Marshal.load(Marshal.dump([1, "two", :three, 4.5, { a: [nil, true] }]))
p Marshal.load(Marshal.dump(S.new(10, "x"))).to_a
p Marshal.load(Marshal.dump(Plain.new)).instance_variables
p Marshal.load(Marshal.dump(Marshalled.new)).instance_variable_get(:@a)
p Marshal.load(Marshal.dump(Dumped.new)).class
p Marshal.load(Marshal.dump(MyStr.new("q"))).class
p Marshal.load(Marshal.dump(1..8)), Marshal.load(Marshal.dump(1...8))
p Marshal.load(Marshal.dump(/a\d+b/i)).source, Marshal.load(Marshal.dump(/a\d+b/i)).options
p Marshal.load(Marshal.dump(Rational(3, 4))), Marshal.load(Marshal.dump(Complex(1, 2)))
p Marshal.load(Marshal.dump("stér")).encoding.to_s
p Marshal.load(Marshal.dump("bin".b)).encoding.to_s
p Marshal.load(Marshal.dump(Encoding::UTF_8))
round = Marshal.load(Marshal.dump([shared, shared]))
p round[0].equal?(round[1])
p Marshal.load(Marshal.dump(Hash.new(7)))[:missing]
p Marshal.dump(1).encoding.to_s
p Marshal.load(Marshal.dump("abc"), freeze: true).frozen?
seen = []
Marshal.load(Marshal.dump([1, 2]), ->(o) { seen << o.class; o })
p seen

[proc {}, method(:puts), Class.new, Module.new, Object.new.tap { |o| def o.x; end }].each do |bad|
  Marshal.dump(bad)
rescue TypeError => e
  puts "#{e.class}: #{e.message.sub(/0x[0-9a-f]+/, "0xXX")}"
end
begin
  Marshal.dump([[1]], 1)
rescue ArgumentError => e
  p e.message
end
a = [1]
seen2 = []
Marshal.load(Marshal.dump([a, a, :s, nil, true, "x"]), ->(o) { seen2 << o.inspect; o })
p seen2
frozen = Marshal.load(Marshal.dump({ a: ["x"] }), freeze: true)
p frozen.frozen?, frozen[:a].frozen?, frozen[:a][0].frozen?
