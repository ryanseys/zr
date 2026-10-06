x = 41

# A Method object's `call` stands between the eval and the scope
# that wrote it, and it has no locals, no cref and no block to
# lend. ruby walks out to the nearest frame written in ruby
# (rb_vm_get_ruby_level_next_cfp), so the eval still reads `x`;
# zr read the builtin's frame and raised NameError.
p method(:eval).call("x + 1")

def inner
  y = 7
  method(:eval).call("y * 2")
end
p inner

# A block frame is written in ruby, so the walk stops there.
p [2, 3].map { |i| method(:eval).call("x + i") }

# `self` is the receiver the Method carries, not the frame's.
p method(:eval).call("self")
p 7.method(:instance_eval).call("self + 1")
p String.method(:class_eval).call("def shout = upcase; :defined")
p "hi".shout

# The eval's own frame is labelled for the frame it took its
# scope from, and the rows below it name what it came through.
begin
  method(:eval).call("raise 'boom'")
rescue => e
  puts e.backtrace.first(3).map { |row| row.split(":in ").last }
end
