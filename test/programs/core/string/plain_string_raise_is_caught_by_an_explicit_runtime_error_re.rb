begin
  raise "just a string"
rescue RuntimeError => e
  puts "caught runtime: #{e.send(:message)}"
end
