# An uninitialized constant inside interpolation raises NameError at run time.
# The interpolation never gets a value from that part, because the raise
# comes first.

module Engine
end

def cost
  "cost #{Engine::DEFAULT_COST}"
end

def try
  yield
rescue NameError => e
  e.class
end

p try { cost }

# a reachable interpolation still works, and is not disturbed by the probe that
# looks for the raise (it emits the value once and hands the text on)
X = 3
def fine = "n=#{X} s=#{X.to_s} f=#{1.5} a=#{[1, 2]}"
p fine

i = 0
def bump(n) = n + 1
s = "#{bump(i)}#{bump(i)}"
p s
p i
