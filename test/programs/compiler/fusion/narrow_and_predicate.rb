# `if v.is_a?(C) && other_cond` narrows `v` to C inside the
# then-arm just like the bare `if v.is_a?(C)` form. So a call
# inside the then-arm passes a C to the callee.

def consume(s)
  s.length
end

class C
  attr_accessor :n
  def initialize; @n = 1; end
end

arr = ["hello", C.new]
v = arr[0]
allow = true
if v.is_a?(String) && allow
  puts consume(v)
end
