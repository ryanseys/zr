# Time value in string interpolation calls #to_s
t = Time.at(0).utc
puts "at '#{t}'"
t2 = Time.at(3661).utc
puts "T=#{t2} end"
puts "#{Time.at(0).utc}"
