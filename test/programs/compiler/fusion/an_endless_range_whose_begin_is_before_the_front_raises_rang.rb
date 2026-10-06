# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# an endless range whose begin is before the front raises RangeError too
begin
  a = [[1, 2, 3], "x"]
  a[0][-10..] = [9]
rescue RangeError => e
  puts "#{e.class}: #{e.message}"
end

