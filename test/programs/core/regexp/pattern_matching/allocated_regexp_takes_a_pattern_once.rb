# `Regexp.new` is `Class#new`: `allocate` makes the husk and
# `initialize` seats the pattern in it. A subclass that builds its
# source in its own initialize therefore keeps what it gave to `super`.
class Wrapped < Regexp
  def initialize(source) = super("(#{source})")
end

r = Wrapped.new("a+")
p r.class
p r.source
p r.options
p r.match("xaaay")[1]

# A husk answers no pattern until one is seated, and takes only one.
bare = Regexp.allocate
p bare.class
begin
  bare.source
rescue TypeError => e
  p [e.class, e.message]
end
bare.send(:initialize, "b+", Regexp::IGNORECASE)
p bare.source
p bare.options
p bare.match?("ZBB")
begin
  bare.send(:initialize, "c+")
rescue TypeError => e
  p [e.class, e.message]
end

# The husk of a subclass is a regexp from the start, so one marshals and
# converts like any other.
p Wrapped.allocate.class
p Marshal.load(Marshal.dump(r)).class
p Marshal.load(Marshal.dump(r)).source
p Regexp.new(r).source
p Regexp.new("d+", nil).source

