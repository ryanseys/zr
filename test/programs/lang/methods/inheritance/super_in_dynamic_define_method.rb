# `super` inside a `define_method` whose NAME is not a literal symbol. The
# block body gets its method context (the name and the owner) at run time.
#
# The dynamic form is the one metaprogramming actually uses -- a name computed
# in a loop is the whole reason to reach for `define_method` -- so this is the
# shape a delegation or wrapper macro hits.
#
# The explicit-argument form resolves to Base#who. The bare form raises
# ruby's OWN RuntimeError about implicit argument passing (see
# `tests/zsuper_in_define_method.rb`), not a NoMethodError.

class Base
  def who(*a) = "base#{a.inspect}"
end

name = :who

explicit = Class.new(Base) { define_method(name) { |*a| "dyn(" + super(*a) + ")" } }
begin
  p explicit.new.who(9)
rescue NoMethodError => e
  puts "explicit: #{e.class}: #{e.message}"
end

bare = Class.new(Base) { define_method(name) { super } }
begin
  p bare.new.who
rescue => e
  puts "bare: #{e.class}: #{e.message}"
end

# The LITERAL-name form is correct and must stay so.
lit = Class.new(Base) { define_method(:who) { |*a| "lit(" + super(*a) + ")" } }
p lit.new.who(1)
