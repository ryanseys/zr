# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# a start before the front raises IndexError
begin
  a = [1, 2, 3]
  a[-9, 1] = [0]
rescue IndexError => e
  puts e.class
end

