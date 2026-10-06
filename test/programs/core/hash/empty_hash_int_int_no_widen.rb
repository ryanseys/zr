# `h = {}; h[parts[0]] = v` where `parts` comes from a `split` result
# (or any expression that returns an Array of Strings). The key is a
# String, so the empty hash gets String keys:
#
# 1. with an Integer value.
# 2. with a String value.
#
# Sibling check: a literal-keyed `h = {}; h[200] = "OK"` gets Integer
# keys and String values.

def build_str_keyed_int_val(s)
  parts = s.split("/")
  h = {}
  h[parts[0]] = 1
  h
end

def build_str_keyed_str_val(s)
  parts = s.split("/")
  h = {}
  h[parts[0]] = "v"
  h
end

def build_int_keyed
  h = {}
  h[200] = "OK"
  h[404] = "NotFound"
  h
end

h1 = build_str_keyed_int_val("a/b")
puts h1["a"]            # 1

h1b = build_str_keyed_str_val("a/b")
puts h1b["a"]           # v

h2 = build_int_keyed
puts h2[200]            # OK
puts h2[404]            # NotFound
