# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- each_char on string, outer int c ---
def f10
  c = 7
  "abc".each_char do |c|
    puts c + "!"
  end
  puts c
end
f10
# a!
# b!
# c!
# 7

