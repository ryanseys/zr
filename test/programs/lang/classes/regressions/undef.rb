# UndefNode -- `undef foo` inside a class body.
#
# CRuby raises NoMethodError if the undef'd method is called.
#
# This test verifies that defining + calling another method on the
# same class still works after undef -- undef removes only the
# named method, not the whole class.

class T_undef_C
  def foo = "foo"
  def bar = "bar"
  undef foo
end

c = T_undef_C.new
puts c.bar     # bar

# Multi-name form: `undef foo, bar`. Defining a third method `baz` and
# undef'ing the other two verifies that exactly the named methods are
# removed.
class T_undef_D
  def foo = "foo"
  def bar = "bar"
  def baz = "baz"
  undef foo, bar
end

puts T_undef_D.new.baz # baz
