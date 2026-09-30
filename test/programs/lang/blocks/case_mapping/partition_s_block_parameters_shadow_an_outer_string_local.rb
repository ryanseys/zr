# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- partition on an Integer Array, outer string n ---
def f8
  n = "outer"
  parts = [1, 2, 3, 4, 5].partition { |n| n > 2 }
  puts parts[0].length      # 3
  puts parts[0][0]          # 3
  puts parts[0][1]          # 4
  puts parts[0][2]          # 5
  puts parts[1].length      # 2
  puts parts[1][0]          # 1
  puts parts[1][1]          # 2
  puts n                    # outer
end
f8

