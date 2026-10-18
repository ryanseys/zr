# ruby runs a String trap command in the interrupted frame, so a write
# from the command changes that frame's local. zr lends the command a
# snapshot of a method's locals when the method keeps them only in its
# frame record, so the write stays in the snapshot and the method returns
# 2 where ruby returns 99.
trap(:USR1, "z = 99")
def m(y)
  z = y + 1
  Process.kill(:USR1, $$)
  z
end
p m(1)
