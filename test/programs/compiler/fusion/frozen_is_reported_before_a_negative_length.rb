# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# check ORDER matches CRuby: frozen wins over negative length...
begin
  a = [1, 2, 3].freeze
  a[1, -1] = [9]
rescue => e
  puts e.class
end

