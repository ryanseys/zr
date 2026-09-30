# A string interpolation ("...#{x}...") keeps its full length, also when
# the result is larger than 4096 bytes.
#
# A view renderer can join `io << a; io << b; io << c` into a single
# `io << "...#{}..."`, and the result can be a large HTML page.

big = "A" * 5000
out = "[#{big}]"
# Full length must survive, and both ends must be intact (a mid-string
# clamp would keep the head but drop the closing bracket).
puts out.length
puts out[0, 1]
puts out[out.length - 1, 1]
