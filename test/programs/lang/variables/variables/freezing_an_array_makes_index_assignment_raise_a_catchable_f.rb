a = [1, 2, 3]
a.freeze
begin
  a[0] = 9
rescue FrozenError => e
  puts e.send(:message)
end
puts a[0]
