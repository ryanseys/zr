puts 7 + 5, 7 - 5, 7 * 5, 7 / 2, -7 / 2, 7 % 3, -7 % 3, 7 % -3
puts 7 < 5, 7 <= 7, 7 > 5, 7 >= 8, 7 == 7, 7 != 7, 7 == :seven
puts 4611686018427387903 - 1, -4611686018427387904 + 1
x = 10
x += 5
x -= 1
x *= 2
puts x
i = 0
sum = 0
while i < 10
  sum = sum + i
  i += 1
end
puts sum
until i == 0
  i -= 1
end
puts i
puts !nil, !false, !0, !!nil
puts nil && 1, 2 && 3, nil || 4, 5 || 6, false || nil
y = nil
y ||= 8
y &&= y + 1
puts y
def early(n)
  return :small if n < 3
  :big
end
puts early(1), early(5)
puts(if false then 1 end)
puts def m; end
puts 1 / 0
