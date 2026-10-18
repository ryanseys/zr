# ruby runs a String trap command in the interrupted frame, and the
# command sees that frame's locals, also of a method that never reads its
# binding: zr lends the command a snapshot of the frame's locals.
trap(:USR1, "p binding.local_variables")
def m(y)
  z = y + 1
  Process.kill(:USR1, $$)
  z
end
m(1)
def k(a, b = 2, *r, c:, **o, &blk)
  d = [a, b]
  Process.kill(:USR1, $$)
  d
end
trap(:USR1, "p binding.local_variables.sort, a, c, d, r, o")
p k(1, c: 3)
