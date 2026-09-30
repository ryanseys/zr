# Defining an instance `[]` must not drop the builtin Hash#[] case from the
# polymorphic `[]` dispatch. A symbol-keyed Hash indexed through a (block
# param) receiver of unknown type still reads the Hash value, not nil.
class Box
  def [](key)
    nil
  end
end

pins = [{ name: "app", path: "/a.js" }, { name: "lib", path: "/b.js" }]
pins.each { |p| puts p[:name] + " -> " + p[:path] }
puts pins.map { |p| p[:name] }.join(",")

# the user-defined [] still dispatches for a real Box receiver
b = Box.new
p b[:anything].nil?
