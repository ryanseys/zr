begin
  File.binread(".")
  puts "binread string succeeded"
rescue => e
  puts e.class
  puts e.message.include?("Is a directory")
end

begin
  File.binread(".").bytes
  puts "binread bytes succeeded"
rescue => e
  puts e.class
  puts e.message.include?("Is a directory")
end
