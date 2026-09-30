f = [1, 2]
f.freeze
begin
  f[0], x = 5, 6
rescue FrozenError => e
  puts e.send(:message)
end
