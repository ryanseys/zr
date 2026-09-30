# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- then on int receiver, outer string v ---
def f18
  v = "hello"
  out = 42.then { |v| v + 1 }
  puts out
  puts v
end
f18
# 43
# hello

