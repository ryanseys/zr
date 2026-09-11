# Interrupt, unlike the other signals, is reported before the process
# ends by SIGINT.
at_exit { puts :handler }
raise Interrupt

__END__
handler
#@ stderr
core/process/an_uncaught_interrupt_is_reported_and_ends_by_sigint.rb:4:in '<main>': Interrupt (Interrupt)
#@ signal 2
