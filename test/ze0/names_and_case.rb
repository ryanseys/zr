LIMIT = 10
GREETING = "hi"

def describe(n)
  case n
  when 0 then "zero"
  when 1, 2 then "small"
  when 3..5 then "medium"
  when Float then "float"
  else "large"
  end
end

$seen = 0
@memo = nil

p LIMIT
p GREETING
p Float::INFINITY
p Integer
p LIMIT + 1

p describe(0)
p describe(2)
p describe(4)
p describe(1.5)
p describe(99)

p(case
  when LIMIT > 100 then :huge
  when LIMIT > 5 then :big
  else :small
  end)
p(case 7 when 1 then :one end)

$seen += 1
$seen += 1
p $seen
p $never_assigned

@memo ||= [GREETING]
@memo ||= ["ignored"]
p @memo
p @never_set

flag = nil
flag ||= "on"
p flag
kept = 1
kept &&= kept + 1
p kept
gone = nil
gone &&= 99
p gone

p 1 && 2
p nil && 2
p false || :fallback
p 1 || :unused
p !true
p !nil
p LIMIT > 5 ? "over" : "under"

n = 0
n += 2 while n < 6
p n
puts "modifier" if n == 6
puts "unless" unless n.zero?

p 5.send(:+, 6)
p GREETING.public_send(:upcase)
p GREETING.respond_to?(:upcase)
p GREETING.respond_to?(:nope)
p 3.method(:*).call(4)
__END__
10
"hi"
Infinity
Integer
11
"zero"
"small"
"medium"
"float"
"large"
:big
nil
2
nil
["hi"]
nil
"on"
2
nil
2
nil
:fallback
1
false
true
"over"
6
modifier
unless
11
"HI"
true
false
12
