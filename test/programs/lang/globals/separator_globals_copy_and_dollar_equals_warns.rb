# $/ and $-0 keep a plain frozen copy of a String subclass, and $= warns
# under the deprecated category that it does nothing, on a read and on
# an assignment.
sub = Class.new(String)
str = sub.new("abc")
str.instance_variable_set(:@ivar, 1)
verbose = $VERBOSE
$VERBOSE = nil
$/ = str
p $/.frozen?, $/.instance_of?(String), $/.instance_variable_defined?(:@ivar), $/ == str
$-0 = sub.new("xyz")
p $/.class, $/
$/ = "\n"
$VERBOSE = verbose

Warning[:deprecated] = true
x = $=
p x
p($= = "_")
p $=
