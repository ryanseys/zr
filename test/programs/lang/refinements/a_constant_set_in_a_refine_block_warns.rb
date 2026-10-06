# A constant or a class variable set in a refine block goes to the module
# around the block, with a warning.
module M
  refine String do
    FOO = 123
    @@foo = 456
    def shout = upcase
  end
end
p M::FOO, M.class_variable_get(:@@foo)
using M
p "a".shout
