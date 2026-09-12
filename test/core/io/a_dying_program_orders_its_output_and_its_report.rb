# The report of an uncaught exception goes through the `$stderr` OBJECT, so
# the order it lands in follows each stream's own buffer rather than any
# flush of ze0's choosing.
#
# With both streams sent to one place, the report queues behind whatever the
# program already wrote, so the output comes first -- and an at_exit handler
# that writes goes out before the report of its own raise. (The order between
# two streams on two descriptors is not visible to a case, which keeps stdout
# and stderr apart; test/rt/no_method.rb holds that one.)
$stderr = $stdout

at_exit { puts "at_exit wrote this" }
$stdout.write("a plain write\n")
puts "a line through puts"
warn "a warning"
raise "the program gave up"

__END__
a plain write
a line through puts
a warning
at_exit wrote this
core/io/a_dying_program_orders_its_output_and_its_report.rb:16:in '<main>': the program gave up (RuntimeError)
#@ exit 1
