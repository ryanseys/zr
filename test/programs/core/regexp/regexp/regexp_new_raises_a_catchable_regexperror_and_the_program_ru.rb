# A bad `Regexp.new("...")` raises a catchable RegexpError, and the
# program runs on after the rescue.
begin
  r = Regexp.new("[invalid")
  puts "no error raised"
rescue => e
  puts "caught: " + e.class.to_s + ": " + e.message
end
puts "after rescue"

# Valid pattern still compiles.
r2 = Regexp.new("hello")
puts "world hello".match?(r2)
