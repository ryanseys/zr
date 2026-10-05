# collect_concat concatenates what to_ary gives and appends on nil. The
# block that map gives each has the arity of the program's block; other
# iterators give a block of any arity.
mk = Object.new
def mk.to_ary = [:a, :b]
nl = Object.new
def nl.to_ary = nil
p [1, mk, 2].each_entry.collect_concat { |i| i }, [1, nl, 2].each_entry.collect_concat { |i| i }.size
bad = Object.new
def bad.to_ary = "x"
p(([1, bad].each_entry.collect_concat { |i| i } rescue $!.class))
class Ary2
  include Enumerable

  def each(&b)
    p b.arity
    yield 1
  end
end
Ary2.new.map { |a, b| }
Ary2.new.map { |a| }
Ary2.new.sort_by { |x| x }
Ary2.new.collect(&:to_s)
