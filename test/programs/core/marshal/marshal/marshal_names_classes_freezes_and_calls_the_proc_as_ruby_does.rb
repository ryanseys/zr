# Marshal.dump writes a class by its own name (not a name method the
# program wrote), with the name's encoding, and the cause of an
# exception; Marshal.load with freeze: interns Strings and freezes
# without the program's freeze, calls the proc for a link only once its
# object is whole, and keeps a Time's zone and ivars and a Regexp's ivars.
class Named; def self.name = "Foo"; end
module NamedMod; def self.name = "Foo"; end
class Multibyteぁあぃい; end
class StrSub < String; def self.name = "Foo"; end
S = Struct.new(:a); class S; def self.name = "Foo"; end
p Marshal.dump(Named), Marshal.dump(NamedMod), Marshal.dump(Multibyteぁあぃい), Marshal.dump(Named.new)
p Marshal.dump(StrSub.new("")), Marshal.dump(S.new("m"))
p((Marshal.dump(Class.new(Range).new(1, 2)) rescue [$!.class, $!.message.sub(/0x\h+/, "X")]))
o = Object.new
def o.foo = 1
p((Marshal.dump(o) rescue [$!.class, $!.message]))
e = (raise "a" rescue (raise ArgumentError, "b" rescue $!))
p Marshal.load(Marshal.dump(e)).cause&.message
# load: freeze
a = Marshal.load(Marshal.dump(["foobar", "foobar", {k: "v"}]), freeze: true)
p a.frozen?, a[0].frozen?, a[0].equal?(a[1]), a[2].frozen?
class NoFreeze; def freeze = raise("called"); end
p Marshal.load(Marshal.dump(NoFreeze.new), freeze: true).frozen?
# load: proc
seen = []
r = Marshal.load(Marshal.dump([1, [2, "x"]]), proc { |v| seen << v.inspect; v.is_a?(Integer) ? v * 10 : v })
p r, seen
rec = [1]; rec << rec
seen = []
Marshal.load(Marshal.dump(rec), proc { |v| seen << v.inspect; v })
p seen
# Time
t = Time.new(2000, 1, 2, 3, 4, 5, "-04:00")
t.instance_variable_set(:@foo, "bar")
t2 = Marshal.load(Marshal.dump(t))
p t2.instance_variable_get(:@foo), t2.utc_offset, t2.zone
lt = Time.at(0)
p Marshal.load(Marshal.dump(lt)).zone == lt.zone
# Regexp ivars
re = Regexp.new("x")
re.instance_variable_set(:@regexp_ivar, 1)
p Marshal.load(Marshal.dump(re)).instance_variables
p((Marshal.load("\x04\bm\x0bString") rescue [$!.class, $!.message]))
p((Marshal.load("\x04\bo:\x0bComparable\x00") rescue [$!.class, $!.message]))
a = "foo" + "bar"
b = "foo" + "bar"
p((-a).equal?(-b))
o = Marshal.load(Marshal.dump(["foo" + "bar", "foobar"]), freeze: true)
p o[0].equal?(o[1])
arr = []
Struct.new("Brittle", :a)
Marshal.load("\x04\bI[\vI\"\ahi\a:\x06EF:\t@fooi\ni\x0F@\x06@\x06IS:\x14Struct::Brittle\x06:\x06af\x060\x06:\n@clueI\"\tnone\x06;\x00FI[\b;\b:\x06b:\x06c\x06:\t@twoi\a\x06:\t@zooI\"\bant\x06;\x00F", proc { |v| arr << v; v }, freeze: true)
p arr, arr.map(&:frozen?)
class UD
  attr_reader :v
  def initialize(v = 1) = @v = v
  def _dump(_) = @v.to_s
  def self._load(s) = new(s.to_i)
end
seen = []
u = UD.new(3)
Marshal.load(Marshal.dump([u, u]), proc { |x| seen << x.class; x })
p seen
p((Marshal.load("\x04\bo:\tFile\001\001:\001\005@path\"\x10/etc/passwd") rescue [$!.class, $!.message]))
bad = Object.new
def bad._dump(_) = 0
p((Marshal.dump(bad) rescue [$!.class, $!.message]))
class UserDefined
  attr_reader :a, :b
  def initialize = (@a = "stuff"; @b = @a)
  def _dump(depth) = Marshal.dump([:stuff, :stuff])
  def self._load(data)
    a, b = Marshal.load(data)
    obj = allocate
    obj.instance_variable_set(:@a, a)
    obj.instance_variable_set(:@b, b)
    obj
  end
end
class UserDefinedWithIvar
  attr_reader :a, :b, :c
  def initialize = (@a = "stuff"; @a.instance_variable_set(:@foo, :UserDefinedWithIvar); @b = "more"; @c = @b)
  def _dump(depth) = Marshal.dump([:stuff, :more, @foo])
  def self._load(data)
    a, b, foo = Marshal.load(data)
    obj = allocate
    obj.instance_variable_set(:@a, a)
    obj.instance_variable_set(:@b, b)
    obj.instance_variable_set(:@c, b)
    obj.instance_variable_set(:@foo, foo)
    obj
  end
end
arr = []
Marshal.load("\x04\b[\tu:\x10UserDefined\x18\x04\b[\aI\"\nstuff\x06:\x06EF@\x06u:\x18UserDefinedWithIvar>\x04\b[\bI\"\nstuff\a:\x06EF:\t@foo:\x18UserDefinedWithIvarI\"\tmore\x06;\x00F@\a@\x06@\a", proc { |o| arr << o.class; o })
p arr
