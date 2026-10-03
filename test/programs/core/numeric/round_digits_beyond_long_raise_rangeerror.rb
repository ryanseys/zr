[2**64, -(2**64), 2**31].each do |d|
  begin
    p 1.5.round(d)
  rescue RangeError => e
    puts "#{e.class}: #{e.message}"
  end
  begin
    p 15.round(d)
  rescue RangeError => e
    puts "#{e.class}: #{e.message}"
  end
  begin
    p 1.5.round(d, half: :even)
  rescue RangeError => e
    puts "#{e.class}: #{e.message}"
  end
end
