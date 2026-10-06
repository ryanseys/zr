# Module.constants with no argument lists the constants of each lexical
# scope and of Object, as rb_mod_s_constants does. With an argument it
# is Module#constants on Module.

module Outer
  X = 1
  class Inner
    Y = 2
    names = Module.constants
    p names.include?(:X), names.include?(:Y), names.include?(:String)
  end
end
p Module.constants(false), Module.singleton_methods(false).include?(:constants)
p Module.constants.include?(:Outer), Module.constants.include?(:Inner)

