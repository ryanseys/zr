# Proc closures capture outer locals, and a write in the proc changes
# the captured local.

# Escaping closure with mutation
def make_counter
  n = 0
  proc { n = n + 1; n }
end

c = make_counter
puts c.call
puts c.call
puts c.call

# Read-only escaping closure
def make_adder(base)
  proc { |n| n + base }
end
add5 = make_adder(5)
puts add5.call(3)
puts add5.call(10)

# Non-escaping closure with multiple captures and mutation
def apply_twice(x)
  total = 0
  count = 0
  doubler = proc { |n| total = total + n * 2; count = count + 1 }
  doubler.call(x)
  doubler.call(x)
  puts total
  puts count
end
apply_twice(5)

# Two procs capturing the same local — mutations must propagate
def make_pair
  shared = 100
  inc = proc { shared = shared + 1 }
  inc.call
  inc.call
  shared
end
puts make_pair
