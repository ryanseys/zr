# `return` written at the top level ends the program. This is also true
# inside a `rescue` clause, an `ensure`, or a `begin/end while`. The exit
# status is 0 and `at_exit` still runs, both of which say this is an ordinary
# end and not an error.
at_exit { puts "at_exit ran" }

puts "start"

begin
  raise "boom"
rescue RuntimeError => e
  puts "rescued #{e.message}"
  return
end

puts "never printed"
