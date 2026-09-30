# The core's type questions at a site whose receiver's class the body
# does not know: the cell holds the builtin, and the site answers what
# a class's rank settles, and calls for the rest.
module Shape; end
class Node; end
class Num < Node; include Shape; end
class Var < Node; end
class Big < Num; end

def isa(o, k) = o.is_a?(k)
def kof(o, k) = o.kind_of?(k)
def inst(o, k) = o.instance_of?(k)
def nilq(o) = o.nil?
def frz(o) = o.frozen?
def sz(o) = o.size
def len(o) = o.length

n = Num.new
b = Big.new
v = Var.new
# Classes the rank settles, both ways, deep and shallow.
p [isa(n, Num), isa(n, Node), isa(n, Object), isa(n, BasicObject), isa(n, Var), isa(n, Big)]
p [isa(b, Num), isa(b, Node), isa(v, Num), kof(b, Node), kof(v, Big)]
# A module is a chain walk, which the builtin makes.
p [isa(n, Shape), isa(b, Shape), isa(v, Shape), isa(n, Kernel), isa(n, Comparable)]
# Special constants: a fixnum, a flonum, a symbol, nil, true.
p [isa(1, Integer), isa(1, Numeric), isa(1, Comparable), isa(1, String), isa(1.5, Float), isa(:s, Symbol)]
p [isa(nil, NilClass), isa(nil, Object), isa(true, TrueClass), isa(1 << 70, Integer)]
# A class as the receiver: its own class is its singleton class.
p [isa(String, Class), isa(String, Module), isa(String, String), isa(Comparable, Module), isa(Comparable, Class)]
# A singleton class of its own, and a module extended into one object.
s = Num.new
def s.hi = 1
e = Var.new
e.extend(Shape)
p [isa(s, Num), isa(s, Node), isa(e, Shape), isa(e, Var), inst(s, Num), inst(e, Var)]
# What is neither a class nor a module raises, from the builtin.
[3, "x", nil].each do |bad|
  begin
    isa(n, bad)
  rescue TypeError => err
    puts "#{err.class}: #{err.message}"
  end
  begin
    inst(n, bad)
  rescue TypeError => err
    puts "#{err.class}: #{err.message}"
  end
end
# instance_of? asks the real class, not the chain.
p [inst(n, Num), inst(n, Node), inst(b, Num), inst(1, Integer), inst(1, Numeric), inst(String, Class)]
# nil? and frozen? of every kind of receiver.
p [nilq(nil), nilq(1), nilq(n), nilq("x"), nilq(false)]
p [frz(1), frz(:s), frz(nil), frz(n), frz(n.dup.freeze), frz(+"x"), frz("x".dup.freeze), frz(1.5)]
# size and length: Array's, a subclass's, Hash's, String's, a reader's.
class Row < Array; end
class Sized
  attr_reader :size, :length
  def initialize = (@size = 7; @length = 8)
end
p [sz([1, 2, 3]), len([]), sz(Row.new([1, 2])), sz({ a: 1 }), len("héllo"), sz(Sized.new), len(Sized.new)]
# A class of the program's own that answers the question itself.
class Liar
  def is_a?(k) = :liar
  def nil? = true
  def frozen? = :no
  def size = -1
end
l = Liar.new
p [isa(l, Liar), nilq(l), frz(l), sz(l)]
# A redefinition after the sites have run moves the stamp; the cells
# find the new body.
p [isa(3, Integer), sz([1]), nilq(4), inst(5, Integer)]
class Integer
  def is_a?(k) = :redefined
  def nil? = :redefined
  def instance_of?(k) = :redefined
end
class Array
  def size = :redefined
end
p [isa(3, Integer), sz([1]), nilq(4), inst(5, Integer)]
# A module included into a class after the site has answered for it.
module Late; end
p isa(n, Late)
class Num; include Late; end
p isa(n, Late)
# `case` asks `===` of each `when`: Module's is the class test, and
# anything else's is its own.
class Odd
  def self.===(x) = x.is_a?(Integer) && x.odd?
end
def kind(x)
  case x
  when Big then :big
  when Num then :num
  when Shape then :shape
  when Odd then :odd
  when Integer then :int
  when 10..20 then :teen
  when /\Ah/ then :h
  when Float, Symbol then :float_or_symbol
  when nil then :nil
  when String then :string
  else :other
  end
end
p [Big.new, Num.new, e, 3, 4, 1.5, :s, nil, "hi", "yo", Var.new, 12.0, [1]].map { |x| kind(x) }
# Module#=== of a class that is not the subject's, of a module, and of
# a class receiver.
p [Num === b, Big === n, Shape === b, Comparable === 3, Class === String, Module === Comparable, Integer === 1.0]
