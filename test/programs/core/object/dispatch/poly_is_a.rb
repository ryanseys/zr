# `is_a?(Klass)` on a value of unknown type. It must match the
# built-in classes (Integer, String, Float, nil, true, false, Symbol,
# Array, Hash, Range) and user classes. A subclass instance matches
# its ancestors, but an ancestor instance does not match a subclass.
#
# A mixed array yields each element, and the type test sends it
# to the correct branch. The
# trailing Bar.new must select the `is_a?(Bar)` arm AND the
# Foo.new before it must NOT match `is_a?(Bar)` (subclass-only).

class Foo
  def name; "foo"; end
end
class Bar < Foo
  def name; "bar"; end
end

arr = [42, "hello", :sym, 1.5, nil, true, false, [1, 2], Foo.new, Bar.new]
arr.each do |x|
  if x.is_a?(Integer)
    puts "Integer #{x}"
  elsif x.is_a?(String)
    puts "String #{x}"
  elsif x.is_a?(Symbol)
    puts "Symbol #{x.to_s}"
  elsif x.is_a?(Float)
    puts "Float"
  elsif x.is_a?(NilClass)
    puts "Nil"
  elsif x.is_a?(TrueClass)
    puts "True"
  elsif x.is_a?(FalseClass)
    puts "False"
  elsif x.is_a?(Array)
    puts "Array"
  elsif x.is_a?(Bar)
    puts "Bar"
  elsif x.is_a?(Foo)
    puts "Foo"
  else
    puts "?"
  end
end
