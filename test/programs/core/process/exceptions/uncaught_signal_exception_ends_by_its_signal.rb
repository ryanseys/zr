# The handlers run, nothing is reported, and the process ends by the
# signal itself.
at_exit { puts :handler, $!.class }
raise SignalException, "TERM"

