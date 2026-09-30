begin
  File.read(".")
  puts "read succeeded"
rescue => e
  puts e.class
  puts e.message.include?("Is a directory")
end
