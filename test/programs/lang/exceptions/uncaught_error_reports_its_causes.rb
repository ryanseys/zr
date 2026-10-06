# The report of an uncaught exception names each cause after it, each
# once, as full_message does.
class Outer < StandardError; end

def a = raise("a")

def b
  a
rescue
  raise Outer, "b"
end

b

