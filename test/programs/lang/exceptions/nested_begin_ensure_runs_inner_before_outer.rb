begin
  begin
    puts "inner body"
  ensure
    puts "inner ensure"
  end
ensure
  puts "outer ensure"
end
