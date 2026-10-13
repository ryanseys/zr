# ruby runs a String trap command in the interrupted frame, and the
# command sees that frame's locals. zr keeps a method's locals in an
# Env only when the method itself reads its binding or evals, so the
# command sees no locals of the method and prints [].
trap(:USR1, "p binding.local_variables")
def m(y)
  z = y + 1
  Process.kill(:USR1, $$)
  z
end
m(1)
