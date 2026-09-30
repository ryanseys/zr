# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- each_cons on a String Array, outer int c ---
def f15
  c = 7
  ["a", "b", "c", "d"].each_cons(3) do |c|
    puts c.length
  end
  puts c
end
f15
# 3
# 3
# 7

