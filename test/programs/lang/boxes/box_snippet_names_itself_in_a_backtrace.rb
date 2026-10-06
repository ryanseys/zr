

# A box's snippet names itself differently from every other eval, in three
# places at once: the file is `eval` (not `(eval at f.rb:14)`), the snippet's
# own scope is `<compiled>` (not the caller's), and the frame between them is
# `Ruby::Box#eval` (not `Kernel#eval`).
#
# The LITERAL form is spliced at compile time and still reports the
# program's own file. This file computes the source
# (`["K", ""].first` is opaque to the constant folder), so the eval
# compiles at run time instead.
#
# Oracle: the box cannot see main's `K`, so ruby raises NameError from the
# snippet's own frame.
K = 5
b = Ruby::Box.new
src = ["K", ""].first
p b.eval(src)
