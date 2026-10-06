def grade(n)
  if n >= 90
    "A"
  elsif n >= 80
    "B"
  elsif n >= 70
    "C"
  else
    "F"
  end
end

def classify(n)
  if n < 0
    if n < -10
      "very negative"
    else
      "negative"
    end
  else
    if n == 0
      "zero"
    elsif n > 10
      "big"
    else
      "small"
    end
  end
end

i = 0
s = 0
while i < 100
  s = s + i
  i = i + 1
end
puts s

n = 10
f = 1
while n > 1
  f = f * n
  n = n - 1
end
puts f

w = while false do end
p w

i = 0
until i == 3
  i = i + 1
end
p i

unless i == 3
  puts "no"
else
  puts "yes"
end

unless i == 4
  puts "not four"
end

z = until true do end
p z

puts grade(95)
puts grade(85)
puts grade(75)
puts grade(10)

x = if 1 < 2 then 10 else 20 end
puts x
y = if 1 > 2 then 10 end
p y
puts(if false then 1 else 2 end)

puts classify(-20)
puts classify(-5)
puts classify(0)
puts classify(5)
puts classify(50)

# `begin` with no clause is a grouping, and the memo shape zr's own
# sources are full of.
memo = {}
memo[:k] ||= begin
  1 + 1
end
p memo

def catch_it
  raise "boom"
rescue => e
  "caught #{e.class}: #{e.message}"
end
p catch_it

def by_class(err)
  begin
    raise err, "m"
  rescue TypeError, ArgumentError => x
    "listed #{x.class}"
  rescue StandardError
    "standard"
  end
end
p by_class(ArgumentError), by_class(TypeError), by_class(RuntimeError)

p(begin
  raise "b"
rescue
  42
end)

p(begin
  7
rescue
  :caught
else
  :fine
end)

begin
  raise "outer"
rescue => a
  begin
    raise "inner"
  rescue => b
    p $!.message
  end
  p $!.message, a.message, b.message
end
p $!

class Fussy < StandardError
  def initialize(msg = "fussy") = super
end

begin
  begin
    raise Fussy
  rescue ArgumentError
    p :never
  end
rescue Fussy => e
  p e.message, e.class
end

def deep = raise("down there")
def shallow
  deep
rescue => e
  e.backtrace.first(2)
end
p shallow

def early
  begin
    raise "x"
  rescue => e
    return "returned #{e.message}"
  end
  :never
end
p early, $!

acc = [1, 2, 3].map do |i|
  begin
    raise "e#{i}" if i == 2
    i
  rescue => e
    next e.message
  end
end
p acc

stopped = [1, 2].each do |i|
  begin
    raise "x"
  rescue
    break :stopped
  end
end
p stopped

i = 0
seen = []
while i < 3
  begin
    raise "e" if i == 1
    seen << i
  rescue => e
    seen << e.message
  end
  i += 1
end
p seen
