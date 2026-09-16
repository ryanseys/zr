# A builtin reached through a site's cell, through send, through a
# Method object, through method_missing's fallback, under a refinement
# and with keywords answers as ruby's does, and its frame names it.
a = [3, 1, 2]
p a.push(4), a.send(:pop), a.method(:shift).call, a.public_send(:unshift, 0), a.method(:first).unbind.bind_call(a, 2)
h = { a: 1 }
p h.fetch(:a), h.send(:fetch, :b, 2), (h.fetch(:c) rescue $!.class), h.method(:key?).call(:a), h.fetch(:z) { |k| k }
p (a.push(1, 2, x: 3) rescue $!.class), a.pop(1, 2) rescue p $!.class, $!.message
p ("x".split(",", 2, 3) rescue $!.message), [1].first(1, 2) rescue p $!.message
module Twice
  refine Array do
    def pop = super * 2
  end
end
using Twice
p [5].pop, [5].send(:pop), [5].method(:pop).call
class Sneaky
  def method_missing(name, *args, &blk) = name == :pop ? [:missing, *args] : super
  def respond_to_missing?(name, priv = false) = name == :pop || super
end
p Sneaky.new.pop(1), Sneaky.new.respond_to?(:pop), (Sneaky.new.shift rescue $!.class)
def frames = [1].each { return caller_locations(0, 3).map(&:label) }
p frames.size >= 2
begin
  [].fetch(3)
rescue IndexError => e
  p e.backtrace_locations&.first&.label
end
p [1, 2].sum { |v| v * 2 }, [1, 2].inject(:+), (1..3).reduce(1) { |m, v| m * v }, [[1, 2]].to_h { |a, b| [b, a] }

__END__
[0, 1, 2]
4
3
[0, 1, 2]
[0, 1]
1
2
KeyError
true
:z
ArgumentError
"wrong number of arguments (given 2, expected 0..1)"
"wrong number of arguments (given 2, expected 0..1)"
10
10
10
[:missing, 1]
true
NoMethodError
true
"Array#fetch"
6
3
6
{2 => 1}
