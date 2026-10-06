# Large-integer operations inside begin/rescue work the same as outside.
#
# Exercises every operator on a large-integer local inside a
# begin/rescue. Output values are not the focus — the program must
# build and run.

a = 1
i = 0
while i < 50
  a = a * 2
  i = i + 1
end

# Inside begin/rescue: every binary operator + comparison + to_s/to_i
begin
  b = a + a
  puts b.to_s.length > 0
  c = a - a
  puts c.to_s.length > 0
  d = a * a
  puts d.to_s.length > 0
  e = a / 2
  puts e.to_s.length > 0
  f = a % 7
  puts f.to_s.length > 0
  puts a > 0
  puts a < 0
  puts a >= 0
  puts a <= 0
  puts a == a
  puts a != 0
  puts a.to_s.length > 0
  puts a.to_i > 0
rescue
  puts "caught"
end

# Compound assignment inside begin/rescue. The `+=` family parses
# as LocalVariableOperatorWriteNode, not as a plain write and a call.
begin
  x = a
  x += 1
  x *= 2
  x -= 1
  x /= 2
  x %= 7
  puts x.to_s.length > 0
rescue
  puts "caught"
end

# puts/p of a large integer inside begin/rescue, with one argument and
# with several. `print` is here too.
begin
  puts a
  puts a, a
  print a, "\n"
rescue
  puts "caught"
end
