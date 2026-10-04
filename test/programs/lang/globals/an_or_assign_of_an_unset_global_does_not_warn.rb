# `$g ||= v` tests the global with defined? first, as ruby compiles it,
# so an unset global gives no warning under -w; a plain read does.
$stderr = $stdout
$VERBOSE = true
def f = $lazy_g ||= 42
p f, f
a = $unset_g
$stdout ||= 1
p $lazy2 ||= nil
