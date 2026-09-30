# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- each_slice on an Integer Array, outer string v ---
def f14
  v = "hello"
  [1, 2, 3, 4].each_slice(2) do |v|
    puts v.length
  end
  puts v
end
f14
# 2
# 2
# hello

