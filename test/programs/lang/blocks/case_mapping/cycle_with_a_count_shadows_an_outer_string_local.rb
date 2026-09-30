# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- cycle on an Integer Array with count, outer string x ---
def f12
  x = "outer"
  [1, 2].cycle(2) do |x|
    puts x * 10
  end
  puts x
end
f12
# 10
# 20
# 10
# 20
# outer

