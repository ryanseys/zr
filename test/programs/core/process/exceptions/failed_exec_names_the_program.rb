begin
  exec("/no/such/program-zr")
rescue SystemCallError => e
  puts "#{e.class}: #{e.message}"
end
