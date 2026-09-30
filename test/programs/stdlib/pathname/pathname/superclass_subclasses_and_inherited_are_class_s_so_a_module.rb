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

# `superclass`/`subclasses`/`inherited` are Class's, so a MODULE has none.
puts "-- Class, not Module"
p owner_of(Class, :superclass)
p owner_of(Class, :subclasses)
p owner_of(Class, :inherited)
[:superclass, :subclasses].each do |m|
  begin
    Comparable.public_send(m)
  rescue NoMethodError
    puts "Comparable.#{m}: NoMethodError"
  end
end

