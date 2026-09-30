# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- reject on an Integer Array, outer string n ---
def f7
  n = "drop"
  out = [1, 2, 3, 4].reject { |n| n > 2 }
  puts out.length           # 2
  puts out[0]               # 1
  puts out[1]               # 2
  puts n                    # drop
end
f7

