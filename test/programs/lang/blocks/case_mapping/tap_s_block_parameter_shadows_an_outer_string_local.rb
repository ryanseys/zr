# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- tap on int receiver, outer string v ---
def f16
  v = "hello"
  42.tap do |v|
    puts v + 1
  end
  puts v
end
f16
# 43
# hello

