# Range#max and #min with a count, as range_max and range_min take it:
# any argument, nil too, is a count. It converts as NUM2LONG converts
# (to_int, a Float truncates), so nil and an Array raise TypeError, not
# NoMethodError. A block, or an exclusive end that is not a Number, goes
# to Enumerable, where nil means no count. Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

class Two
  def to_int = 2
  def inspect = "Two"
end

[[1..4, "1..4"], [-1...4, "-1...4"], [(..4), "..4"], [("a".."e"), "'a'..'e'"], [(1.0..3.5), "1.0..3.5"]].each do |r, name|
  [nil, [], "2", 2, 2.7, Two.new, 0, -1, 10].each do |n|
    try("(#{name}).max(#{n.inspect})") { r.max(n) }
    try("(#{name}).min(#{n.inspect})") { r.min(n) }
  end
  try("(#{name}).max") { r.max }
  try("(#{name}).min") { r.min }
end

# An endless range: the endless check comes before the count's.
try("(1..).max([])") { (1..).max([]) }
try("(1..).min([])") { (1..).min([]) }
try("(1..).min(nil)") { (1..).min(nil) }

# A beginless range: the beginless check of min comes first.
try("(..4).min([])") { (..4).min([]) }
try("(..'c').max(1)") { (.."c").max(1) }
try("(...'c').max") { (..."c").max }
try("(...'c').max(1)") { (..."c").max(1) }

# A block, or an exclusive end that is not a Number: Enumerable takes
# nil as no count.
try("max(nil) {}") { (1..4).max(nil) { |a, b| b <=> a } }
try("min(nil) {}") { (1..4).min(nil) { |a, b| b <=> a } }
try("max(2) {}") { (1..4).max(2) { |a, b| b <=> a } }
try("min(2) {}") { (1..4).min(2) { |a, b| b <=> a } }
try("max([]) {}") { (1..4).max([]) { |a, b| a <=> b } }
try("('a'...'e').max(nil)") { ("a"..."e").max(nil) }
try("('a'...'e').max(2)") { ("a"..."e").max(2) }
try("('a'...'e').max([])") { ("a"..."e").max([]) }
try("(..4).max(nil) {}") { (..4).max(nil) { |a, b| a <=> b } }
try("(1..).min(nil) {}") { (1..).min(nil) { |a, b| a <=> b } }

# Too many arguments.
try("max(1, 2)") { (1..4).max(1, 2) }
try("min(1, 2)") { (1..4).min(1, 2) }
