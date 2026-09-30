# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- each_byte on string, outer string b ---
def f11
  b = "kept"
  "AB".each_byte do |b|
    puts b + 1
  end
  puts b
end
f11
# 66
# 67
# kept

