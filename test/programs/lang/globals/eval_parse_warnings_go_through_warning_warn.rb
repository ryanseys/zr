# A parse-time warning of eval'd code goes through Warning.warn (a
# swapped $stderr sees it), and one of the -w level shows only under
# a true $VERBOSE.
require "stringio"
out = StringIO.new
$stderr = out
$VERBOSE = false
eval("{foo: 1, foo: 2}")
$VERBOSE = true
eval("defined?(foo); 1")
eval("x = 1 if (1..2)")
$stderr = STDERR
p out.string.lines.map { _1.sub(/\(eval at .*?\)/, "(eval)") }
