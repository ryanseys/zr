module Store
end

begin
  puts Store::MISSING
rescue NameError => e
  puts "NameError: #{e.message}"
end
