# The continuation extension warns that callcc is obsolete as it loads,
# through rb_warn, which says nothing while $VERBOSE is nil. Kernel#warn
# is silent then too.
$VERBOSE = nil
require "continuation"
warn "not shown"
p callcc { |k| k.call(:back) }
$VERBOSE = false
warn "shown"

