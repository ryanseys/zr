# A `class` or `module` may name the scope it goes in. The name is the
# path, and the class is the SAME one a nested body would have declared.
module Outer
  X = :outer_x

  class Base
    def kind = :base
  end

  module Mixin
    def mixed = :mixed
  end
end

# A qualified name opens ONE cref frame: the body searches `Outer::Inner`
# and then whatever encloses the statement, never `Outer`. So `Y` is
# found here and `X` is not, though a body written inside `module Outer`
# would have found both.
class Outer::Inner < Outer::Base
  include Outer::Mixin

  Y = :inner_y

  def kind = [super, Y, mixed]

  def reach = [defined?(Y), defined?(X)]
end

module Outer::Side
  Z = :side_z

  def self.z = Z
end

# The scope may be deeper than one name, and the path may be reopened.
class Outer::Inner
  def second = :again
end

class Outer::Inner::Deep
  def where = :deep
end

p Outer::Inner.name
p Outer::Inner.superclass
p Outer::Inner.ancestors.take(4)
p Outer::Inner.new.kind
p Outer::Inner.new.reach
p Outer::Inner.new.second
p Outer::Inner::Deep.new.where
p Outer::Inner::Deep.name
p Outer::Side.z
p Outer::Side.name
begin
  Outer::Inner.new.instance_eval { X }
rescue NameError => e
  p e.class
end

# A nested body still nests: `Nested` inside `module Outer` sees `X`.
module Outer
  class Nested
    def reach = [defined?(X), defined?(Y)]
  end
end

p Outer::Nested.new.reach
p Outer::Nested.name

# Sorted: a class row is registered before the first statement runs, so
# the ORDER `constants` answers in is zr's registration order and not
# ruby's assignment order.
p Outer.constants.sort
p Outer::Inner.constants.sort
