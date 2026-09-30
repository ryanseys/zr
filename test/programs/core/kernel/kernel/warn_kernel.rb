# `warn arg, ...` writes each arg to stderr with a newline, as
# Kernel#warn does.
#
# The test checks the stderr output of warn too. at_exit blocks run in
# LIFO order after the main program ends.
at_exit { puts "from at_exit" }
warn "hello stderr"
puts "after warn"
warn "two", "args"
puts "done"
