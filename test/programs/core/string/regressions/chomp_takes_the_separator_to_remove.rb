# String#chomp with an explicit separator argument strips that
# suffix, not the default newline.
puts "hello!".chomp("!").inspect
puts "hello\n".chomp.inspect
puts "hello\r\n".chomp.inspect
puts "hello".chomp("!").inspect
puts "hello\n\n".chomp("").inspect
