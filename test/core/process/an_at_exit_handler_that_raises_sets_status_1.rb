# The handler's error is reported, the next handler still runs, and the
# program ends with status 1.
at_exit { puts :second }
at_exit { raise "x" }
puts 1

__END__
1
second
#@ stderr
core/process/an_at_exit_handler_that_raises_sets_status_1.rb:4:in 'block in <main>': x (RuntimeError)
#@ exit 1
