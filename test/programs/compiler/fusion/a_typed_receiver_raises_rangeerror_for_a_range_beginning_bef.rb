# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# a range beginning before -len raises RangeError on a typed receiver too
begin
  a = [1, 2, 3]
  a[-9..0] = [1]
rescue RangeError => e
  puts "#{e.class}: #{e.message}"
end

