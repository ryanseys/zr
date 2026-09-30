# Array#[]= splice exceptional cases: exact CRuby exception class + message.

# ...and over an out-of-range range (typed receiver)
begin
  a = [1, 2, 3].freeze
  a[-9..0] = [1]
rescue => e
  puts e.class
end

