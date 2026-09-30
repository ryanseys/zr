# A lambda's `return` is its own, and never leaves the caller.
def lam
  l = lambda { return :from_lambda }
  [l.call, :after]
end
p lam
