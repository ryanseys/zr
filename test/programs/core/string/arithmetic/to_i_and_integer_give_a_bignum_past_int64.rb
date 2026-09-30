# String#to_i and Integer() on input past the int64 range give a
# Bignum. They do not raise RangeError, and they do not saturate.

begin
  "99999999999999999999".to_i
  puts "no exception"
rescue RangeError
  puts "to_i raised RangeError"
end

begin
  "ffffffffffffffff0".to_i(16)
  puts "no exception"
rescue RangeError
  puts "to_i(16) raised RangeError"
end

begin
  Integer("99999999999999999999")
  puts "no exception"
rescue RangeError
  puts "Integer raised RangeError"
end

# In-range values still work.
puts "42".to_i
puts "ff".to_i(16)
puts Integer("-1000")
