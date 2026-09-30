begin
  puts "body"
rescue => e
  puts "rescued"
else
  puts "else ran"
ensure
  puts "ensure2 ran"
end

