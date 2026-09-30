# Test Symbol and String methods

# Symbol
s = :hello
puts s  # hello

# String methods
str = "Hello, World!"
puts str.length      # 13
puts str.upcase      # HELLO, WORLD!
puts str.downcase    # hello, world!
puts str.include?("World")  # true
puts str.include?("xyz")    # false

# String concatenation
a = "foo"
b = "bar"
c = a + b
puts c  # foobar

# to_s on integers
n = 42
puts n.to_s  # 42
