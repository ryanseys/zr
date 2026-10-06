# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# start before the front
begin
  a = [[1, 2, 3], "x"]
  a[0][-5, 1] = [9]
rescue IndexError => e
  puts "#{e.class}: #{e.message}"
end

