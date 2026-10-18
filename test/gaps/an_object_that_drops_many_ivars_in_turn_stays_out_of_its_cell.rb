# An object that removes many instance variables one after another stays
# out of its slot, even when few enough remain to fit: each removal of a
# variable that is not the last adds a new branch under one shape, and
# past eight branches CRuby gives the object a "too complex" shape, whose
# fields live in a table. zr has no shape tree (shapes-lite, W6 P5), so it
# moves the variables back into the cell.
require "objspace"

def embedded?(o) = ObjectSpace.dump(o).include?('"embedded":true')

c = Class.new do
  def initialize
    @a = nil
    @b = nil
    @c = nil
  end
end
o = c.new
o.instance_variable_set(:@foo, 5)
%i[@x @y @z @w @v @u @t @s @r @q].each { |name| o.instance_variable_set(name, 1) }
p embedded?(o)
%i[@x @y @z @w @v @u @t @s @r @q].each { |name| o.remove_instance_variable(name) }
o.remove_instance_variable(:@foo)
p embedded?(o), o.instance_variables
