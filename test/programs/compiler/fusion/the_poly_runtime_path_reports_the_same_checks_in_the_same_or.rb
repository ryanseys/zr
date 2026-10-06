# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# the same order through the poly runtime path
begin
  a = [[1, 2, 3].freeze, "x"]
  a[0][1, -1] = [9]
rescue => e
  puts e.class
end
begin
  a = [[1, 2, 3].freeze, "x"]
  a[0][-10..1] = [9]
rescue => e
  puts e.class
end

