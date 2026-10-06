# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# a range whose begin is before the front raises RangeError (not IndexError)
begin
  a = [[1, 2, 3], "x"]
  a[0][-10..1] = [9]
rescue RangeError => e
  puts "#{e.class}: #{e.message}"
end

