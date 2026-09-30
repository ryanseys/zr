h = { a: 1 }
h.freeze
begin
  h[:b] = 2
rescue FrozenError => e
  puts e.send(:message)
end
puts h.length
