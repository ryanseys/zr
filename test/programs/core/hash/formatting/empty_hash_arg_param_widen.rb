# A method that stores String values into its hash parameter works when
# the caller passes an empty `{}` literal.

def store_str(receiver)
  receiver["k"] = "v"
  receiver["k2"] = "v2"
  receiver
end

h = store_str({})
puts h["k"]                # v
puts h["k2"]               # v2

def store_sym_int(h)
  h[:a] = 1
  h[:b] = 2
  h
end

s = store_sym_int({})
puts s[:a].to_s            # 1
puts s[:b].to_s            # 2

# Mixed values widens to str_poly_hash.
def store_mixed(r)
  r["i"] = 7
  r["s"] = "x"
  r
end

m = store_mixed({})
puts m["i"].to_s           # 7
puts m["s"]                # x
