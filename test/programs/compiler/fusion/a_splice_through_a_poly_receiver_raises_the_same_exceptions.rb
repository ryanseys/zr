# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# poly receiver (an element that is a typed array at runtime): same exceptions.
# negative length
begin
  a = [[1, 2, 3], "x"]
  a[0][1, -1] = [9]
rescue IndexError => e
  puts "#{e.class}: #{e.message}"
end

