# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- each on an Integer Array, outer string v ---
def f1
  v = "hello"
  [1, 2, 3].each do |v|
    puts v * 10
  end
  puts v
end
f1
# 10
# 20
# 30
# hello

