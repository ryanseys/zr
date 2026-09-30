# A top-level method that yields, called with a literal block, and the
# result assigned (`x = measure { ... }`). The block runs, and the
# variable gets the value of the method's last statement.

def measure
  yield
  42
end

x = measure { puts "block" }
puts x.to_s         # 42

# Last stmt is a local read (after locals + yield).
def assign_last
  yield
  z = 99
  z
end

w = assign_last { puts "hi" }
puts w.to_s         # 99

# String return type
def str_call
  yield
  "result"
end

s = str_call { puts "in" }
puts s
