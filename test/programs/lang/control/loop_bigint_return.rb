# A method whose loop-carried local grows into a Bignum (d = d * 2) returns
# that Bignum, and the caller can use the result.
def doublings(n)
  d = 1
  i = 0
  while i < n
    d = d * 2
    i += 1
  end
  d
end
puts doublings(100)

def factorial(n)
  r = 1
  i = 1
  while i <= n
    r = r * i
    i += 1
  end
  r
end
puts factorial(30)
x = doublings(3)
puts(x > 0 ? "positive" : "nonpositive")
