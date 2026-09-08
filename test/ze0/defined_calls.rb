# frozen_string_literal: true

# `defined?(f(a))` answers "method" only when the call resolves AND
# every argument is itself defined, so one undefined argument makes the
# whole answer nil.

p defined?(puts(1))
x = 5
p defined?(puts(x))
p defined?(puts(Missing))
p defined?([1, 2].map(Missing))
p defined?(nothing_here(1))
p defined?(puts(@never_set))

# `defined?(super)` asks whether the walk above this method finds one.
class Base
  def f = 1
end

class Sub < Base
  def f = defined?(super)
  def g = defined?(super)
end

p Sub.new.f
p Sub.new.g

# Outside a method, and in a method Object itself holds, there is no
# super to find.
def top = defined?(super)
p top
p defined?(super)

# `{ x: }` and `f(a:)` write the value as the name alone.
value = 7
p({ value: })
def kw(a:, b: 2) = [a, b]
a = 9
p kw(a:)

# A `&b` parameter is the block channel, and a body the runtime
# installs binds it the same way a `def` does.
class Runtime
  define_method(:named) do |n, &blk|
    [n, blk&.call]
  end
end
p Runtime.new.named(1) { :given }
p Runtime.new.named(2)
p proc { |&b| b&.call }.call { :inner }
__END__
"method"
"method"
nil
nil
nil
nil
"super"
nil
nil
nil
{value: 7}
[9, 2]
[1, :given]
[2, nil]
:inner
