# Method-level rescue return value with string-returning bodies.
# The method gives the last expression of the body, or of the rescue
# clause when it rescues. Both branches give a String, so the method
# gives a String.

# Both branches return string.
def fetch(s)
  raise "empty" if s == ""
  "got " + s
rescue
  "default"
end
puts fetch("data")
puts fetch("")

# Rescue body with multiple statements. Last is the value.
def parse(s)
  raise "blank" if s == ""
  "len=" + s.length.to_s
rescue
  msg = "fallback"
  msg + "!"
end
puts parse("hi")
puts parse("")

# A method body with a rescue, and an explicit `return X` in the body.
# The return value is also a String.
def explicit(s)
  raise "neg" if s == ""
  return "early " + s
rescue
  "late"
end
puts explicit("yes")
puts explicit("")
