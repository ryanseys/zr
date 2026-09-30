# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- tap on string receiver, outer int s ---
def f17
  s = 99
  "abc".tap do |s|
    puts s + "!"
  end
  puts s
end
f17
# abc!
# 99

