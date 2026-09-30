r = /
  \d+  # a number
  -
  \d+  # another number
/x
puts r.match?("123-456")
