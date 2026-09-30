begin
  raise TypeError, "wrong type"
rescue ArgumentError, TypeError => e
  puts "caught one of: #{e.send(:message)}"
end

