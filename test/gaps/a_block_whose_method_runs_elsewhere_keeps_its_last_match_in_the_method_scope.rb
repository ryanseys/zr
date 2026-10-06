# CRuby keeps `$~` in the special variables of the method's scope, so a
# proc sees the match of its last call after the method returned, and a
# thread whose block was written in the method keeps one `$~` for all
# its calls. zr reaches `$~` through the frame of the method while it
# runs on the same stack; otherwise each call of the block has its own,
# because a block frame without an Env of its own cannot find the
# method's.
def scope
  pr = proc do |s|
    s =~ /(.)/ if s
    $~ && $~[0]
  end
  Thread.new do
    pr.("x")
    p pr.(nil)
  end.join
  pr
end
later = scope
later.("z")
p later.(nil)
p $~
