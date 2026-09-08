# frozen_string_literal: true

def wrap(x)
  "<#{x}>"
end

name = "world"
count = 3
puts "hello, #{name}! #{count} #{count * 2} #{1 + 2}"
puts "#{wrap(1)} #{wrap("two")} #{wrap(nil)}"
puts "no interpolation at all"
puts "trailing #{name}"
puts "#{name} leading"

letters = ["a", "b", "c"]
p letters
p letters.length
p letters[0]
p letters.reverse
p [1, [2, 3], [], nil, true, :sym, 4.5]
p [].empty?

sizes = { "small" => 1, "large" => 9 }
p sizes
p sizes["large"]
p sizes.keys
p sizes.values
p({ a: 1, b: [2, 3] })
p({})

p (1..4).to_a
p (1...4).to_a
p (1..4).include?(2)
p ("a".."d").to_a

s = "abc"
p s.upcase
p s + "def"
p s * 2
s += "!"
p s
p "#{s.length} #{letters.size} #{sizes.size}"

# The magic comment above: a literal is one frozen object, an
# interpolated string is fresh, and `+` and `dup` both unfreeze.
p "abc".frozen?
p "abc".equal?("abc")
p "#{name}".frozen?
p (+"abc").frozen?
p "abc".dup.frozen?

# Splats spread through ruby's own `to_a` and `to_hash` rules.
xs = [2, 3]
p [1, *xs, 4]
p [*xs]
p [*xs, *xs]
p [*nil]
p [*1]
p [*(1..3)]
p [*{ a: 1 }]

kw = { a: 1, b: 2 }
p({ **kw })
p({ c: 0, **kw })
p({ **kw, a: 9 })
p({ **kw, **kw })

# `&.` answers nil without calling, on nil ALONE.
none = nil
p none&.size
p "abc"&.size
p false&.to_s
p none&.map { |v| v }
p [4, 5]&.map { |v| v * 2 }
p({ a: { b: 1 } }[:a]&.fetch(:b))
p({ a: { b: 1 } }[:z]&.fetch(:b))

# Adjacent literals are one string.
one = 1
p "x#{one}" \
  "y#{one + 1}"
p "left" "right"
__END__
hello, world! 3 6 3
<1> <two> <>
no interpolation at all
trailing world
world leading
["a", "b", "c"]
3
"a"
["c", "b", "a"]
[1, [2, 3], [], nil, true, :sym, 4.5]
true
{"small" => 1, "large" => 9}
9
["small", "large"]
[1, 9]
{a: 1, b: [2, 3]}
{}
[1, 2, 3, 4]
[1, 2, 3]
true
["a", "b", "c", "d"]
"ABC"
"abcdef"
"abcabc"
"abc!"
"4 3 2"
true
true
false
false
false
[1, 2, 3, 4]
[2, 3]
[2, 3, 2, 3]
[]
[1]
[1, 2, 3]
[[:a, 1]]
{a: 1, b: 2}
{c: 0, a: 1, b: 2}
{a: 9, b: 2}
{a: 1, b: 2}
nil
3
"false"
nil
[8, 10]
1
nil
"x1y2"
"leftright"
