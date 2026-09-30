# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- map on an Integer Array, outer string i ---
def f4
  i = "outer"
  out = [10, 20, 30].map { |i| i + 1 }
  puts out[0]               # 11
  puts out[1]               # 21
  puts out[2]               # 31
  puts i                    # outer
end
f4

