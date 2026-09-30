# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# splicing into a frozen array raises FrozenError
begin
  a = [1, 2, 3].freeze
  a[0, 1] = [9]
rescue FrozenError => e
  puts e.class
end

