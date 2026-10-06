# Built-in exception classes (StandardError, RuntimeError, ...) and
# nested user classes (M::Inner) work as values, the same way flat
# user-class constants do.

# Shape A: built-in exception class as value.
def takes_class(c)
  puts c.name
end

takes_class(StandardError)
takes_class(RuntimeError)
takes_class(ArgumentError)

# Class object via a local — round-trip through a value slot.
c = StandardError
puts c.name

# Shape B: nested user class as value. The value survives a
# round-trip through a method return, and `==` confirms it.
module M
  class Inner
  end
end

def make
  M::Inner
end

c2 = make
puts c2 == M::Inner ? "round-trip ok" : "round-trip BROKEN"
