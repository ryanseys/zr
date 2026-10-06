# Marshal.load(freeze: true) interns a String only when it is bare: one
# with instance variables or modules of its own is frozen in place, so
# links to it and its own ivars still name the same object.
module Mod1; end

str = +"test"
str.instance_variable_set(:@self, str)
objects = Marshal.load(Marshal.dump([str, str]), freeze: true)
p objects.map(&:frozen?)
p objects[0].equal?(objects[1])
p objects[0].equal?(objects[0].instance_variable_get(:@self))

ivar = +""
ivar.instance_variable_set(:@iv, 1)
copy = Marshal.load(Marshal.dump(ivar), freeze: true)
p [copy.frozen?, copy.instance_variables]

extended = +"abc"
extended.extend(Mod1)
copy = Marshal.load(Marshal.dump(extended), freeze: true)
p [copy.frozen?, copy.is_a?(Mod1)]

plain = Marshal.load(Marshal.dump(["x", "x"]), freeze: true)
p [plain[0].frozen?, plain[0].equal?(plain[1]), plain[0].equal?(-"x")]
