# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# promoting a frozen typed array still raises FrozenError
begin
  a = [[1, 2, 3].freeze, "x"]
  a[0][1, 1] = ["s"]
rescue FrozenError => e
  puts e.class
end

