# A method called only inside string interpolation gets its parameter
# type from that call: `cap(name)` inside `"#{...}"` is the only call
# site for `cap`, so its `s` param is a String.

def cap(s)
  s + "_cap"
end

name = "frob"
puts "lv_#{cap(name)}"

# Same shape with two args, one of which is also a method call
def join_with(a, b)
  a + "_" + b
end

x = "hello"
y = "world"
puts "wrapped(#{join_with(x, y)})"

# Nested interpolation containing a method call whose param widens to int
def inc(n)
  n + 1
end

puts "next=#{inc(10)}"

# Method whose param widens to bool via interpolated boolean call
def bang(p)
  if p
    "YES"
  else
    "no"
  end
end

flag = true
puts "answer: #{bang(flag)}"
