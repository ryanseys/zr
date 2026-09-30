puts 1
begin
  return 5 if true
ensure
  puts 2
end
puts 3
