# The handler's error is reported, the next handler still runs, and the
# program ends with status 1.
at_exit { puts :second }
at_exit { raise "x" }
puts 1

