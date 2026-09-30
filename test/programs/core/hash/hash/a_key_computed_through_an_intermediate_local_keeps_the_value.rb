# `h[pp + "_k"] = ap` where pp/ap are intermediate locals (themselves
# elements of a split result). The hash gets String keys and String
# values, from the types of pp and ap.

def build(a, b)
  pa = a.split("/")
  pb = b.split("/")
  h = {}
  i = 0
  while i < pa.length
    pp = pa[i]
    ap = pb[i]
    h[pp + "_k"] = ap
    i += 1
  end
  h.length
end

puts build("a/b/c", "x/y/z")
