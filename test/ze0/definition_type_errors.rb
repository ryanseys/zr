# frozen_string_literal: true

# A definition ruby RAISES on is a definition that runs and raises, not a
# program that cannot be compiled: the statement lowers to the `TypeError`
# in its place, a `rescue` around it catches it, and the class stays
# exactly as it was. Both message lines are ruby's, and the second names
# where the CONSTANT was made -- the first declaring statement, so a
# reopen leaves it standing.

class Parent; end
class Other; end

class Bare; end
begin
  class Bare < Parent; end
rescue TypeError => e
  p [e.class, e.message]
end
p Bare.superclass.to_s

# Restating the same parent is fine, and a bare reopen agrees with it by
# saying nothing.
class Kid < Parent
  def a = 1
end
class Kid < Parent
  def b = 2
end
class Kid
  def c = 3
end
k = Kid.new
p [k.a, k.b, k.c, Kid.superclass.to_s]

begin
  class Kid < Other; end
rescue TypeError => e
  p e.message
end

# The KIND has to agree too, in both directions, and ruby names the LEAF.
module Outer; end
class Outer::Inner; end
begin
  module Outer::Inner; end
rescue TypeError => e
  p e.message
end

module Mixin
  def m = :m
end
begin
  class Mixin; end
rescue TypeError => e
  p e.message
end
p Mixin.instance_of?(Module)

# A builtin's kind and its parent are the runtime's, so both guards are
# asked where the statement stands: a reopen may restate the real parent
# and may not invent one.
class String < Object
  def shout = upcase + "!"
end
p "hi".shout

begin
  class String < Parent; end
rescue TypeError => e
  p e.message
end

# `module String` is the same guard on the kind, and it is
# `test/lang/exceptions/a_definition_ruby_raises_on_is_rescuable.rb` that
# holds it: ruby has no source location for a builtin, so the second line
# is empty, and a program that ALSO reopens the class disagrees there.

# The native exception hierarchy reopens the same way.
class StandardError
  def tag = "[#{self.class.name}]"
end

begin
  raise ArgumentError, "bad"
rescue => e
  p [e.tag, e.message]
end

begin
  module Comparable; end
rescue TypeError => e
  p e.message
end
p Comparable.instance_of?(Module)
__END__
[TypeError, "superclass mismatch for class Bare"]
"Object"
[1, 2, 3, "Parent"]
"superclass mismatch for class Kid"
"Inner is not a module\nze0/definition_type_errors.rb:43: previous definition of Inner was here"
"Mixin is not a class\nze0/definition_type_errors.rb:50: previous definition of Mixin was here"
true
"HI!"
"superclass mismatch for class String"
["[ArgumentError]", "bad"]
true
