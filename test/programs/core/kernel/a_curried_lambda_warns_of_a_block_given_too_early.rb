# A curried lambda warns of a block given before its last argument, and
# uses the block that comes with the last one.
b = lambda { |x, y, &blk| blk.call(x + y) }.curry
b = b.call(2) { raise }
p b.call(3) { |x| x + 4 }
