# caller with a level past the stack and a count of 0 gives [], and a
# method of a class with no permanent name is labeled by its name alone.
def depth = caller(0).size

t = depth
p caller(t + 5, 0), caller(t + 5, 1), caller(t + 5), caller(0, 0)

foo = Class.new
def foo.bar = raise("in bar")
begin
  foo.bar
rescue => e
  p e.backtrace_locations.first.label, e.backtrace.first[/'.*'/]
end

foo::Bar = Class.new
def (foo::Bar).baz = raise("in baz")
begin
  foo::Bar.baz
rescue => e
  p e.backtrace_locations.first.label, e.backtrace.first[/'.*'/]
end

