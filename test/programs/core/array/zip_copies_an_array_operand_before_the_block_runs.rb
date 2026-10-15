# Array#zip takes the first items of each operand before the first row:
# a copy of an Array, so a block that changes an operand or the receiver
# changes only the receiver's later elements.
a = [1, 2, 3]
b = [4, 5, 6]
c = [7, 8, 9]
a.zip(b, c) do |row|
  p row
  a[2] = 30
  b[1] = 50
  c.clear
end
p b, c

d = [1, 2]
e = [3, 4, 5]
p d.zip(e) { e << 6 }, e
f = [1, 2, 3]
p f.zip([], [9]) { |row| f.pop if row[0] == 1; p row }
p [1, 2].zip([3, 4]) { break :early }
