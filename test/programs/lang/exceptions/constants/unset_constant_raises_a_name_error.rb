begin
  puts UNDEFINED_CONST
rescue NameError => e
  puts "caught: #{e.message}"
end
