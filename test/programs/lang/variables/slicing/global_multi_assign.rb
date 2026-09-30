# Multi-assignment into global variables sets every target from the
# right-hand side, not only the first. This includes a non-Integer RHS
# (String / Float / Array) and a splat-rest target.
$g1, $g2 = 1, 2
p [$g1, $g2]

$s1, $s2 = "x", "y"
p [$s1, $s2]

$f1, $f2 = 1.5, 2.5
p [$f1, $f2]

$pp, $qq = [10, 20]
p [$pp, $qq]

# mixed local and global targets
first, $g = 1, 2
p [first, $g]

# splat-rest target collects into an array global
$x, *$rest = 1, 2, 3, 4
p $x
p $rest

# heterogeneous targets
$h1, $h2, $h3 = "a", 2, 3.0
p [$h1, $h2, $h3]
