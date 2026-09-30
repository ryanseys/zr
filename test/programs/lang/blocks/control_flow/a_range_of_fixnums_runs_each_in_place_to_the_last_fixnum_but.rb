s = 0
(1..5).each { |i| s += i }
p s
p (1...4).each { |i| s += i }
p s
p (3..1).each { raise }
p (1...1).each { raise }
p (1..2).each { |i| break i * 100 if i == 2 }
p (2**62 - 2..2**62 - 1).each { |i| p i }
p (2**62 - 3...2**62 - 1).each { |i| p i }
p (1.0..2).each { } rescue p $!.class
p ("a".."c").each { |c| print c }
p (1..).each { |i| break i if i > 2 }
p (1..3).each { |i| p caller(0)[1][/in '(.*)'/, 1] if i == 1 }
n = 0
(1..1_000_000).each { |i| n += i & 1 }
p n
class Range; def each = :redefined; end
p (1..3).each { raise }
