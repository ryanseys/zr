# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# negative length via the start,len scalar form too
begin
  a = [1, 2, 3]
  a[0, -1] = 5
rescue IndexError => e
  puts "#{e.class}: #{e.message}"
end

