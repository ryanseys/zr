# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- partition on a String Array, outer int x ---
def f9
  x = 99
  parts = ["a", "bb", "ccc"].partition { |x| x.length > 1 }
  puts parts[0].length      # 2
  puts parts[0][0]          # bb
  puts parts[0][1]          # ccc
  puts parts[1].length      # 1
  puts parts[1][0]          # a
  puts x                    # 99
end
f9

