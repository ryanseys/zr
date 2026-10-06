# A safe-navigation target writes only when its receiver is not nil:
# `rescue => o&.x` and `for o&.x in list`.
class Box
  attr_accessor :x
end

o = Box.new
begin
  raise "boom"
rescue => o&.x
end
p o.x.message

n = nil
begin
  raise "boom"
rescue => n&.x
end
p n

q = Box.new
for q&.x in [1, 2]; end
p q.x

z = nil
for z&.x in [1, 2]; end
p z

