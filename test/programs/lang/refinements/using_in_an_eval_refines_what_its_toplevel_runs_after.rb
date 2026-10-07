# `using` in an eval with a Binding of the toplevel gives that toplevel a
# cref with the refinement, as rb_mod_using does: its code from then on,
# its blocks, each later eval there (with a Binding or without), and each
# method it defines from then on run under it. A method defined before
# keeps the cref it was defined with.
module M
  refine String do
    def upcase = reverse
    def shout = "#{self}!"
  end
end

s = "hello"
def before(s) = (s.shout rescue "none")
early = binding
p((s.shout rescue "none"))
p s.upcase

b = binding
p eval(%{using M; "hello world".upcase}, b)
p eval(%{"again".upcase}, b)
p s.upcase
p s.shout
p s.public_send(:upcase)
p eval("'abc'.upcase")
p eval("'abc'.upcase", binding)
p early.eval("'early'.upcase")
p before(s)
def after(s) = s.shout
p after(s)
[1].each { p s.upcase }
p proc { s.shout }.call
p s.method(:upcase).call

# `using` in an eval with no Binding refines nothing after it.
module N
  refine Integer do
    def double = self * 2
  end
end
eval("using N")
p((1.double rescue "none"))

# A Binding of a method is not a toplevel: ruby refuses the `using`.
def method_binding = binding
p((eval("using M", method_binding) rescue [$!.class, $!.message]))
