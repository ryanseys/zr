# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# negative length raises IndexError
begin
  a = [1, 2, 3, 4]
  a[1, -2] = [9]
rescue IndexError => e
  puts "#{e.class}: #{e.message}"
end

