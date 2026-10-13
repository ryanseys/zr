# A toplevel def in a box is a method of the box's Object, so the box's
# classes, their singleton methods and its blocks reach it, while main
# does not. A shared module that a box reads keeps its own methods
# (Marshal.load, Math.sqrt), in a new box and in the root box.
box = Ruby::Box.new
box.eval(<<~RUBY)
  def toplevel = :top
  class Foo
    def self.call_toplevel = toplevel
    def call_toplevel = toplevel
  end
RUBY
p box::Foo.call_toplevel
p box::Foo.new.call_toplevel
p box.eval("[1, 2].map { toplevel }")
p respond_to?(:toplevel, true)
begin
  toplevel
rescue NameError => e
  p e.class
end
p box.eval("Math.sqrt(16)")
p box.eval("Marshal.load(Marshal.dump([1, :a]))")
p box.eval("Comparable.instance_method(:between?).owner")
loader = Ruby::Box.root.eval("->(dump) { Marshal.load(dump) }")
p loader.call(Marshal.dump({a: 1}))
p Ruby::Box.root.eval("Math.sqrt(9)")
p Ruby::Box.root.eval("Math::PI.floor")
