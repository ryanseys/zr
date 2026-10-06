# Which CLASS owns a builtin method is part of its behaviour, not a detail of
# reflection: it decides which receivers answer it. This locks the boundaries
# the arity census proved zr had drawn in the wrong place.

require "pathname"
require "tmpdir"

def owner_of(klass, name)
  klass.instance_method(name).owner
rescue NameError
  "absent"
end

# ...while the real spellings still work.
p Regexp.linear_time?(/a*/)
p Pathname.new("/tmp").to_s
p ->(x) { x * 2 }.(3)
p Struct.new(:a)[1].a
require "set"
p Set.new([1]).include?(1)
p (Set.new([1]) | [2]).to_a.sort
