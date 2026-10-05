# Hash methods in the edge cases of CRuby's own tests.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

a = { "ABC" => :t }
b = { "ABC" => :t }
p a.keys[0].equal?(b.keys[0])
p a.keys[0].equal?("ABC".freeze)
var = +"ABC"
c = { var => :t }
p c.keys[0].equal?("ABC".freeze)
p c.keys[0].frozen?, var.frozen?
sub = Class.new(String)
d = { sub.new("ABC") => 1 }
p d.keys[0].class == sub, d.keys[0].frozen?

o = Object.new
def o.to_hash = {}
def o.eql?(x) = true
p({}.eql?(o))
def o.eql?(x) = false
p({}.eql?(o))
p({}.eql?(0))

p({}.hash != 0)
h = { 1 => 2 }
h.shift
p h.hash == {}.hash

p({ "あ": 1 }.inspect)
p({ a: 1, "a!": 1, "0": 1, "@a": 1, "a=": 1, "[]": 1, "a\"b": 1 }.inspect)

x = { a: 1, b: 2, c: 3, d: 4 }
show { x.transform_values! { |v| x.freeze if v == 2; v.succ } }
p x

big = {}
(1..100).each { |k| big[k] = k }
show { big.update({ 1 => 2 }) { big.rehash } }

s = Struct.new(:x) { def hash = [x, ""].hash }
sa = s.new
sb = s.new
sa.x = sb
sb.x = sa
show { sa.hash.is_a?(Integer) }

e = begin
  { "gumby" => 1 }.fetch("gumby" * 20)
rescue KeyError => err
  err
end
p e.message
p e.key == "gumby" * 20

wrapper = Class.new do
  def initialize(obj) = @obj = obj
  def hash = @obj.hash
  def eql?(other) = @obj.eql?(other)
end
bad = [5, true, false, nil, 0.0, 1.72723e-77, :foo, "str"].select do |v|
  { v => 1 }[wrapper.new(v)] != 1
end
p bad

calls = Object.new
class << calls
  attr_accessor :n
  def hash
    @n += 1
    super
  end
end
calls.n = 0
hh = { calls => 42 }
hh.select { true }
hh.reject { false }
p calls.n
