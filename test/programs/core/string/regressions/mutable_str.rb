# Mutable strings: the `<<` mutation path, replace/clear,
# index access, gsub/sub, split, ljust/rjust, downcase/strip/...,
# start_with?/end_with?/empty?/include?, to_s/to_i.

# << (true mutation, not reassignment)
a = "hello"
a << " world"
a << "!"
puts a          # hello world!
puts a.length   # 12

# Build string incrementally
buf = ""
5.times do |i|
  buf << i.to_s
  buf << ","
end
puts buf        # 0,1,2,3,4,

# upcase / reverse / include? on mutable receiver
b = "Hello World"
puts b.upcase                 # HELLO WORLD
puts b.reverse                # dlroW olleH
puts b.include?("World")      # true

# replace / clear
c = "hello"
c.replace("world")
puts c          # world
c.clear
puts c.length   # 0

# [] on mutable string
d = "abcdef"
d << "ghi"
puts d[0]       # a
puts d[-1]      # i
puts d.length   # 9

# gsub on mutable receiver
e = "hello"
e << " world"
puts e.gsub("o", "0")  # hell0 w0rld

# split on mutable receiver
f = "a"
f << ",b,c"
parts = f.split(",")
puts parts.length  # 3

# + creates a new string, does not mutate the receiver
g = "foo"
g << "bar"
h = g + "baz"
puts g        # foobar (unchanged)
puts h        # foobarbaz

# to_s on mutable receiver
tst = "test"
tst << "ing"
puts tst.to_s   # testing

# downcase / strip / capitalize / start_with? / end_with? / empty?
j = ""
j << "Hello"
j << " "
j << "World"
puts j.length             # 11
puts j.downcase           # hello world
puts j.strip              # Hello World
puts j.capitalize         # Hello world
puts j.start_with?("Hello")  # true
puts j.end_with?("World")    # true
puts j.empty?             # false

# sub / gsub on mutable receiver
puts j.gsub("l", "r")        # Herro Worrd
puts j.sub("World", "Ruby")  # Hello Ruby

# to_i via mutable receiver
n = ""
n << "42"
puts n.to_i    # 42

# ljust / rjust
t = ""
t << "hi"
puts t.ljust(10)   # "hi        "
puts t.rjust(10)   # "        hi"

# include?
puts j.include?("World")  # true
puts j.include?("xyz")    # false

puts "done"
