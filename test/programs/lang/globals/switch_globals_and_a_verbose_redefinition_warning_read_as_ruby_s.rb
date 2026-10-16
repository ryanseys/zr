# Run with no special flags; exercise in-program behavior tied to switches
p $VERBOSE, $DEBUG, $-w, $-v, $-d, $-i, $-l, $-p, $-a, $-0, $;, $,
$VERBOSE = true
def x = 1
def x = 2
p [1].frozen?
warn "done"
