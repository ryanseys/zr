# Empty `[]` literal as parameter — deferred element-type resolution
# must converge across caller / param / body. Issues #58 (top-level
# def + instance method) and #84 (inherited dispatch). Was four
# tests; class names don't collide so the merge is straight
# concatenation with shared helpers.


def collect_names(buf)
  buf.push("alpha")
  buf.push("beta")
end
names = []
collect_names(names)
puts names[0]       # alpha
puts names[1]       # beta
puts names.length   # 2
