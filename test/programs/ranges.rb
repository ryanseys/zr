r = (1..3)
p r, (1...3), r.first, r.last, r.min, r.max, r.size, (1...3).size, r.to_a, (1...3).to_a
p r.include?(2), r.include?(4), r === 2, (1..).first(2) rescue p $!
p r.each { |i| print i }, (3..1).to_a, r.begin, r.end, r.exclude_end?, (1...3).exclude_end?
p ("a".."c").to_a, ("a".."c").include?("b")
case 5
when 1..3 then p :low
when 4..6 then p :mid
end
p r.map { |x| x * 2 }, r.select(&:odd?), r.sum, r.reduce(:+)
x, y = 2, 4
p (x..y).to_a, (x...y).count, r == (1..3), r == (1...3), r.eql?(1..3), (1..3).hash == (1..3).hash
p r.cover?(2), r.cover?(9)
p (1..0).to_a, (1..1).to_a
5.times { |i| next if i.odd?; print i }
puts
p (1..3).inject { |a, b| a * b }
p (1..3).to_s, (1..3).inspect, ("a".."b").inspect
