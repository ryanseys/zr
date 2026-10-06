# Time.new reads each part of a time string in base ten, so 08 and 09
# are the eighth and ninth, and its helpers leave no backtrace row and
# no private method a program can list.

p Time.new("2024-08-09 08:09:09", in: "+00:00")
p Time.new("2024-09-08 09:08:07 +09:00")
p Time.new("0999-01-01 00:00:00.09", in: "UTC").subsec
p Time.new("2024-01-01 00:00:00.0800", in: "UTC").subsec
p Time.private_methods(false).sort
begin
  Time.new("2024-08-9 08:09:09")
rescue ArgumentError => e
  p e
  puts e.backtrace
end

