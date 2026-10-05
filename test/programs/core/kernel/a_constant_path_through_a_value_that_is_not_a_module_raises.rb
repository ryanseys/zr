# A constant path that goes through a value which is not a module raises
# a TypeError that names the whole path, and does not crash.
class Outer
  ConstLocation = [__FILE__, __LINE__]
end
def t(l); p [l, yield]; rescue Exception => e; p [l, e.class, e.message]; end
t(1) { Outer.const_source_location(:ConstLocation) == Outer::ConstLocation }
t(2) { Outer.const_source_location("ConstLocation") == Outer::ConstLocation }
t(3) { Object.const_source_location("Outer::ConstLocation") == Outer::ConstLocation }
t(4) { Outer.const_source_location(nil) }
t(5) { Outer.const_source_location("xxx") }
t(6) { Outer.const_source_location("ConstLocation::FILE") }
t(7) { Outer.const_get("ConstLocation::FILE") }
t(8) { Outer.const_defined?("ConstLocation::FILE") }
t(9) { Object.const_source_location("Outer::ConstLocation::FILE") }
