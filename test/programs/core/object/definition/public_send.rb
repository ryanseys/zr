# `recv.public_send(:meth, args)` calls a public method the same way
# `recv.send(:meth, args)` does, in both the Symbol and the String form.

puts "hello".public_send(:upcase)
puts "world".public_send("upcase")
puts 42.public_send(:to_s)

# __send__ also keeps working (existing path).
puts "x".__send__(:upcase)
