# A local of no single type, guarded by `is_a?(String)`, goes as a
# positional arg to a top-level method that uses it as a String.
# The same shape applies to an Integer guard.

def helper_s(s)
  s.length
end

def encode(v)
  return helper_s(v) if v.is_a?(String)
  -1
end

puts encode("hello")
puts encode(42)

def helper_i(i)
  i * 2
end

def double_if_int(v)
  return helper_i(v) if v.is_a?(Integer)
  0
end

puts double_if_int(7)
puts double_if_int("nope")
