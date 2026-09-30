# A module whose method calls `super`, never included anywhere, so nothing says
# what that super answers. The raise for it never returns. The program still
# compiles when the super value goes into a boxed slot, such as an
# interpolation.
# a module whose `super` is interpolated, never included
module Numbered
  def render(text) = "#{super}!"
end
class Plain
  def render(text) = text
end
p Plain.new.render("hi")

# the neighbouring shapes
module Whole
  def render2(text) = super
end
class Plain2
  def render2(text) = text
end
p Plain2.new.render2("ho")

# super interpolated where it DOES resolve
class Base
  def label = "base"
end
class Child < Base
  def label = "#{super}-child"
end
p Child.new.label

# an unresolved super in other value positions
module Orphan
  def a = [super]
  def b = super.to_s
  def c = { k: super }
  def d = super + 1
end
class Other
  def a = 1
  def b = 2
  def c = 3
  def d = 4
end
p [Other.new.a, Other.new.b, Other.new.c, Other.new.d]
