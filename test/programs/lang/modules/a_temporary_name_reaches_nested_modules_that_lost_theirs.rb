# A temporary name reaches each nested module that has no permanent
# name, also one whose own temporary name was cleared, and a constant
# that refers back up the path ends the walk.
m = Module.new
m.const_set(:N, Module.new)
p m::N.name.sub(/0x\h+/, "")
m::N.set_temporary_name("fake_name_under_M")
p m::N.name
m::N.set_temporary_name(nil)
p m::N.name
m::N.const_set(:O, Module.new)
m.const_set(:Recursive, m)
m::N.const_set(:Recursive, m)
m.const_set(:A, 42)
m.set_temporary_name("fake_name")
p [m.name, m::N.name, m::N::O.name]
m.set_temporary_name(nil)
p [m.name, m::N.name, m::N::O.name]
a = Module.new
a.const_set(:B, Module.new)
a::B.const_set(:Back, a::B)
a.set_temporary_name("tmp_a")
p [a.name, a::B.name]
Named = a
p [a.name, a::B.name, a::B::Back.name]
