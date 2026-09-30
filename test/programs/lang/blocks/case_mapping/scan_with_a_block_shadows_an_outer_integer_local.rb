# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- scan with block on string, outer int m ---
def f13
  m = 99
  "a1b2c3".scan(/\d+/) do |m|
    puts m + "!"
  end
  puts m
end
f13
# 1!
# 2!
# 3!
# 99

