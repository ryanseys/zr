# rjust/ljust/center with a width known only at run time (Hash#keys.max)
counts = Hash.new(0)
counts[1] = 1; counts[4] = 1
w = counts.keys.max
p "x".rjust(w)
p "y".ljust(w)
p "z".center(w)
p "ab".rjust(w, "*")
p "cd".ljust(w, "-")
# a literal Integer width
p "s".rjust(5)
p "t".ljust(5, ".")
