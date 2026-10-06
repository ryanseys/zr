# A Time interpolates via its own `to_s` -- it is an Object with a runtime
# table, not a registry class, so `call_user_method` has to find the row.

t = Time.at(1700000000).getutc
puts "at #{t}"
puts "#{t.year}-#{t.month}"
p t.to_s.class
