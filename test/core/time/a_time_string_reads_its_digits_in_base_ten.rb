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

__END__
2024-08-09 08:09:09 +0000
2024-09-08 09:08:07 +0900
(9/100)
(2/25)
[:_load, :inherited, :initialize]
#<ArgumentError: two digits mday is expected after '-': -9 08:09:09>
core/time/a_time_string_reads_its_digits_in_base_ten.rb:11:in 'Time#initialize'
core/time/a_time_string_reads_its_digits_in_base_ten.rb:11:in '<main>'
