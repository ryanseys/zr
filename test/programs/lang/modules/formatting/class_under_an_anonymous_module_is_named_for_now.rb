# A class set as a constant of an anonymous module takes a temporary
# name under the module's #<Module:0x...>; when the module is named,
# everything it holds takes its name for good.
def name_of(mod) = mod.name&.gsub(/0x\h+/, "0xXX")

m = Module.new
m::K = Class.new
class m::Inner; end
module m::Deep; end
m::Deep.const_set(:Leaf, Class.new)
p name_of(m::K), name_of(m::Inner), name_of(m::Deep), name_of(m::Deep::Leaf)
p m::K.inspect.gsub(/0x\h+/, "0xXX")

Named = m
p m::K.name, m::Inner.name, m::Deep.name, m::Deep::Leaf.name

# A class that already has a name keeps it.
class Kept; end
n = Module.new
n::Alias = Kept
Other = n
p Kept.name, n::Alias.name
