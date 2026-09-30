# The cycle this program builds on purpose, and the census it leaves
# behind. A cycle alive at exit is not a defect: it is a ring the
# program never broke, so the census below is recorded as an
# observation rather than gated on.
#
# `a << a` -- the circular reference the generator is supposed to name.
# At exit: cycle leak: 1 objects (Array x1)
# `JSON.generate` on a self-referential array raises JSON::NestingError
# ("Did you try to serialize objects with circular references?"). It must
# not recurse without end. `Array#join` and `<=>` have the same guard.
require "json"
a = [1]
a << a
begin
  JSON.generate(a)
rescue JSON::NestingError => e
  puts e.class
end
