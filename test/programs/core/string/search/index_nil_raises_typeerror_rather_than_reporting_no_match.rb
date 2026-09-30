# String#index(nil) raises TypeError. "No implicit conversion" is not the
# same as "not found", so it does not return nil.
begin
  "hello".index(nil)
  puts "BUG: no raise"
rescue TypeError => e
  puts "TypeError: " + e.message
end
