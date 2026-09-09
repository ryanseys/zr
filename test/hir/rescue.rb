def f
  raise "boom"
end
begin
  f
rescue => e
  puts e.message
end
class E < StandardError; end
begin
  raise E
rescue E => e
  p e
  p $!
end
p $!
begin
  raise E, "with message"
rescue StandardError => e
  p e
end
x = begin
  1
rescue
  2
else
  3
ensure
  puts "ensure"
end
p x
def g
  return 1
ensure
  puts "g ensure"
end
p g
n = 0
begin
  n += 1
  raise "again" if n < 3
  puts "n=#{n}"
rescue
  retry
end
p((raise "m" rescue "rescued"))
begin
  raise 42
rescue TypeError => e
  p e
end
begin
  nope
rescue NoMethodError, NameError => e
  p e.class
end
def h
  yield
ensure
  puts "h ensure"
end
[1].each { |i| h { break } }
puts "after"
begin
  begin
    raise "inner"
  ensure
    puts "inner ensure"
  end
rescue => e
  puts "outer #{e.message}"
end
begin
  raise
rescue RuntimeError => e
  p e
end
def k
  yield
rescue ZeroDivisionError => e
  puts "k: #{e.message}"
  :k
end
p k { 1 / 0 }
i = 0
r = while true
  i += 1
  begin
    break i * 10 if i == 3
  ensure
    puts "loop ensure #{i}"
  end
end
p r
begin
  raise E
rescue Integer
  puts "no"
rescue E
  puts "yes"
end
begin
  begin
    raise "a"
  rescue => e
    raise "b"
  end
rescue => e2
  p e2
end
begin
  raise "q"
ensure
  p $!
end
