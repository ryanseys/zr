# String#to_i past the int64 range gives a Bignum. It does not raise,
# and it does not stop at INT64_MAX or INT64_MIN.

# Below int64 limit: unchanged.
puts "12345".to_i
puts "-67890".to_i

# Past int64 max: a Bignum, so the rescue does not run.
begin
  puts "99999999999999999999999999999".to_i
rescue RangeError
  puts "raised"
end

begin
  puts "-99999999999999999999999999999".to_i
rescue RangeError
  puts "raised"
end

# Exactly INT64_MAX: parses fine, no raise.
puts "9_223_372_036_854_775_807".to_i

# One past INT64_MAX: a Bignum.
begin
  puts "9_223_372_036_854_775_808".to_i
rescue RangeError
  puts "raised"
end
