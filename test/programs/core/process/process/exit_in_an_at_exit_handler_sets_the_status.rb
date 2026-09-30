# Handlers run last first; the status a handler's `exit` gives wins over
# the one the program asked for.
at_exit { exit 3 }
at_exit { puts :first, $!.inspect }
exit 5

