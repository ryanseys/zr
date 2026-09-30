# The chain on repeated_permutation gives the real value. It does not
# crash and does not quietly print "[]".
begin
  puts [1, 2].repeated_permutation(2).to_a.inspect
rescue NoMethodError
  puts "raised NoMethodError"
end
puts "after"
