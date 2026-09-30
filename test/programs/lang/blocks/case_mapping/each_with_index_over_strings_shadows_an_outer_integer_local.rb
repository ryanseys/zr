# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- each_with_index on a String Array, outer int i ---
def f3
  i = 99
  ["a", "b", "c"].each_with_index do |s, i|
    puts s + ":" + i.to_s
  end
  puts i
end
f3
# a:0
# b:1
# c:2
# 99

