# An exit handler that raises leaves its error in `$!` for the handlers
# that run after it, as rb_ec_exec_end_proc does, for END and at_exit.
$stderr = $stdout
at_exit { puts "at_exit: #{$!.message}" }
END { puts "END: #{$!.message}" }
at_exit { raise "second" }
at_exit { raise "first" }
