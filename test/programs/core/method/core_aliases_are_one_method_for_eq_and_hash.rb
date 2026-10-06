# Method#== and #hash compare definitions: CRuby's aliases are one method,
# and methods that it defines apart stay two.
mods = [Array, Hash, String, Symbol, Integer, Float, Numeric, Range, Struct, Data, Regexp, MatchData, IO, File, Dir,
        Enumerable, Comparable, Kernel, Module, Class, Object, BasicObject, Proc, Method, UnboundMethod, Exception,
        Time, Rational, Complex, Set, Enumerator, Enumerator::Lazy, Thread, Thread::Queue, Thread::SizedQueue, Encoding,
        NilClass, TrueClass, FalseClass, ObjectSpace::WeakMap, Fiber, Binding, Random, Process::Status, File::Stat]
mods.each do |m|
  names = (m.instance_methods(false) + m.private_instance_methods(false)).reject { _1.start_with?("_") }
  groups = names.sort.group_by { |n| m.instance_method(n) }.values.select { _1.size > 1 }
  groups.each { |g| puts "#{m}: #{g.sort.inspect}" }
  hashes = names.sort.group_by { |n| m.instance_method(n).hash }.values.select { _1.size > 1 }
  puts "#{m} hash groups differ" if hashes.map(&:sort).sort != groups.map(&:sort).sort
end
a = Array.instance_method(:map)
b = Array.instance_method(:collect)
p [a == b, a.hash == b.hash, a.eql?(b)]
x = [].method(:map)
y = [].method(:collect)
p [x == y, x.hash == y.hash]
o = Object.new
def o.foo = nil
class << o
  alias bar foo
end
p [o.method(:foo) == o.method(:bar), o.method(:foo).hash == o.method(:bar).hash]
p [String.instance_method(:size) == String.instance_method(:length), String.instance_method(:size).hash == String.instance_method(:length).hash]
p [Kernel.instance_method(:send) == Kernel.instance_method(:public_send)]
h = { a => 1 }
p h[b]
