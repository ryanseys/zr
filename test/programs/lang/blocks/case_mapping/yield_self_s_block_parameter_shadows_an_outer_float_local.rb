# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- yield_self with int receiver returning string, outer float v ---
def f19
  v = 3.14
  out = 42.yield_self { |v| v.to_s + "!" }
  puts out
  puts v
end
f19
# 42!
# 3.14
