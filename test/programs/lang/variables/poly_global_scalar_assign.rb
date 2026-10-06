# A global that holds different types across assignments can also get a bare
# scalar (`$g = 42`). The value is boxed, as are the others.
$g = 5
$g = "hello"
$g = [1, 2]
p $g
$g = 42
p $g
$g = :sym
p $g
$g = true
p $g
