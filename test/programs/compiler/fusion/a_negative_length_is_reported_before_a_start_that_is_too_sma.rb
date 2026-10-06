# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# negative length is reported before a too-small index (CRuby checks length first)
begin
  a = [1, 2, 3]
  a[-9, -1] = [5]
rescue IndexError => e
  puts "#{e.class}: #{e.message}"
end
begin
  y = [1, "x"]
  y[-9, -1] = [5]
rescue IndexError => e
  puts "#{e.class}: #{e.message}"
end

