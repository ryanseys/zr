# Empty `[]` literal as parameter — deferred element-type resolution
# must converge across caller / param / body. Issues #58 (top-level
# def + instance method) and #84 (inherited dispatch). Was four
# tests; class names don't collide so the merge is straight
# concatenation with shared helpers.


def push_floats(buf)
  buf.push(1.5)
  buf.push(2.5)
  buf
end
result_pf = push_floats([])
puts result_pf[0]   # 1.5
puts result_pf[1]   # 2.5
