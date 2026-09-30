# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- map on a String Array, outer int s ---
def f5
  s = 42
  words = ["a", "b", "c"]
  up = words.map { |s| s.upcase }
  puts up[0]                # A
  puts up[1]                # B
  puts up[2]                # C
  puts s                    # 42
end
f5

