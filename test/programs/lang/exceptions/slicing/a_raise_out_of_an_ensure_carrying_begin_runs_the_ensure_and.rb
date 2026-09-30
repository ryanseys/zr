def b
  begin
    raise "boom"
  rescue => e
    return "r:#{e.message}"
  ensure
    puts "ensure b"
  end
end
p b

