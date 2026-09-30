# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# ...over a too-small index...
begin
  a = [1, 2, 3].freeze
  a[-9, 1] = [9]
rescue => e
  puts e.class
end

