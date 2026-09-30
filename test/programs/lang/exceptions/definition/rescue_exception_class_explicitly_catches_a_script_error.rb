begin
  raise ScriptError, "script problem"
rescue Exception => e
  puts "caught via Exception: #{e.send(:message)}"
end
