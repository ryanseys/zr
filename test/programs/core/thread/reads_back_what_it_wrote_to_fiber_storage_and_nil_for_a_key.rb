Fiber[:user_id] = 42
puts Fiber[:user_id]

Fiber[:user_id] = 43
puts Fiber[:user_id]

v = Fiber[:not_set]
if v.nil?
  puts "nil_ok"
else
  puts "nil_unexpected"
end
