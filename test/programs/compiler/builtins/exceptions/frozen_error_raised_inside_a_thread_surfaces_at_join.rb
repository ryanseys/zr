a = [1]
a.freeze
t = Thread.new { a[0] = 9 }
begin
  t.join
rescue FrozenError => e
  puts "at join: #{e.send(:message)}"
end
