# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- select on an Integer Array, outer string n ---
def f6
  n = "kept"
  out = [1, 2, 3, 4].select { |n| n > 2 }
  puts out.length           # 2
  puts out[0]               # 3
  puts out[1]               # 4
  puts n                    # kept
end
f6

