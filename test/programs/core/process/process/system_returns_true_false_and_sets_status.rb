# `system` inherits stdio and answers true (exit 0) / false (nonzero),
# setting `$?` either way. A nonzero exit does not raise.

p system("true")
puts $?.exitstatus
p system("false")
puts $?.success?
puts $?.exitstatus
