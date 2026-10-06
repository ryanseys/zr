# A method with no caller still compiles, and the program runs.
# `Util.size_of` has no call site, so its param has no known type.
# Any warning about it names the containing method, as
# "in <Class>.<method>", "in <Class>#<method>" or "in <Mod>.<method>".
# The test asserts only the program output (the warning goes to
# stderr; the harness drops it via 2>/dev/null).

module Util
  def self.size_of(xs)
    xs.length
  end
end

puts "hello"
