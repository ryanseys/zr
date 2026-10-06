puts "hello world" =~ /world/
puts "hello world" =~ /xyz/
puts "hello".match?(/l+/)
puts(/l+/.match?("hello"))
puts("hello" !~ /xyz/)

