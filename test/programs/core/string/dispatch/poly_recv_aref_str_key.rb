# A user-defined `def [](k)` takes its parameter type from the
# caller's arguments. Here the receiver's type is only known at run
# time (a method param that accepts more than one user class), and
# callers pass a String key. Each class's `[]` gets the String key.
# Integer#[] (bit reference) and the Array#[] forms do not apply to
# a String key.

class A
  def [](k)
    "from-A:" + k
  end
end

class B
  def [](k)
    "from-B:" + k
  end
end

def lookup(receiver, key)
  receiver[key]
end

puts lookup(A.new, "alpha")
puts lookup(B.new, "beta")
