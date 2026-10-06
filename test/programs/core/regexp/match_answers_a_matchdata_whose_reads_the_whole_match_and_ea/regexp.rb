
m = "hello world".match(/(\w+) (\w+)/)
puts m[0]
puts m[1]
puts m[2]
puts m.pre_match
puts m.post_match
puts m.to_a
puts m.captures

