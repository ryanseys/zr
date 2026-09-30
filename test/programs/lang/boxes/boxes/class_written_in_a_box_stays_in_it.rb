

# A `class` written in a box belongs to that box: main cannot reach it.
#
# A box's top-level class keeps its bare ruby name -- `Escapee` written in a
# box is called `Escapee`. But in main, `Object.constants`, a bare constant
# read and `defined?` do not see it, and the three agree.

b = Ruby::Box.new
b.eval("class Escapee; def self.hi = 'in box'; end")
p defined?(Escapee)
begin
  p Escapee
rescue NameError => e
  p e.class
end
