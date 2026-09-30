# `class X < <expression>` builds the class at runtime, so its body runs as a
# block. A local write inside that body must open its OWN scope, not
# silently assign the ENCLOSING scope's variable.
#
# A REOPEN (`Foo = Class.new; class Foo ... end`) has a static fallback for
# exactly these bodies.
#
# A runtime-built class body EMITS as a block, which shares the enclosing
# local scope -- but ruby gives a class body its own. The body's names must
# be isolated per body, so neither direction leaks: the outer `y` keeps its
# value, and the body's `y` is invisible outside.

y = 99
class Foo < Struct.new(:a)
  y = 1
  define_method(:from_body) { y }
end
p y
p Foo.new(0).from_body
p defined?(y)
p binding.local_variables
