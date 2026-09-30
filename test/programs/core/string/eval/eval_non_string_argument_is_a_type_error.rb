begin
  eval(123)
rescue TypeError => e
  puts e.message
end
