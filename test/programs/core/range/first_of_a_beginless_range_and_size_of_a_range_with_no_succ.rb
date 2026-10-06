def t
  p yield
rescue RangeError, TypeError => e
  puts "#{e.class}: #{e.message}"
end
t { (..5).first(2) }
t { (..5).first }
t { (1r..3).size }
t { (1.5..).size }
t { (1..3r).size }
t { ("a".."c").size }
t { (..5).size }
