t = Time.now
puts t.to_f - t.to_i > 0.0
puts t.to_i > 1_000_000_000
puts t.to_i < 2_000_000_000
puts t.to_f > 1_000_000_000.0
puts t.to_i == t.to_f.to_i || t.to_i + 1 == t.to_f.to_i

puts Time.at(1234567890).to_i == 1234567890
puts Time.at(0).to_i == 0
puts Time.at(-1).to_i == -1

t2 = Time.at(1234567890.5)
puts t2.to_i == 1234567890
puts (t2.to_f - 1234567890.5).abs < 0.001

a = Time.at(1000.5)
b = Time.at(500.25)
puts ((a - b) - 500.25).abs < 0.0001

puts (Time.at(0) - Time.at(0)).abs < 0.0001

puts ((Time.at(100) - Time.at(200)) + 100.0).abs < 0.0001

# A negative fraction rounds the seconds down
puts Time.at(-0.5).to_i == -1

puts Time.at(0.0).to_i == 0

# Time#to_f has millisecond precision
puts Time.now.to_f * 1000 > 1_000_000_000_000.0

puts Time.at(1).to_i + Time.at(2).to_i == 3

puts (Time.at(1.5).to_f * 1000 - 1500.0).abs < 1.0

puts (Time.at(2000) - Time.at(1000)).to_i == 1000

puts "done"
