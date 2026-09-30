# Block parameters shadow outer differently-typed locals correctly.
# Inside the block, the param has its own type, so a call on it goes to
# the method of that type (e.g. Integer#* for an Integer param, not
# String#*).

# --- each_with_index, outer string i ---
def f2
  i = "outer"
  ["a", "b"].each_with_index do |s, i|
    puts s + i.to_s
  end
  puts i
end
f2
# a0
# b1
# outer

