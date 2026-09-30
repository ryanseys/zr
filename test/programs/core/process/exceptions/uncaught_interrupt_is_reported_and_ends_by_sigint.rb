# Interrupt, unlike the other signals, is reported before the process
# ends by SIGINT.
at_exit { puts :handler }
raise Interrupt

