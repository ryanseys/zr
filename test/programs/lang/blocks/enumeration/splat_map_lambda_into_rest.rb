# Splatting an inline map-of-lambdas into a *args method whose vararg is
# captured by a returned closure. The splat is evaluated once, and a lambda
# that is a block's last value escapes with the block.
def alt(*parsers)
  ->(s) { parsers.map { |pr| pr.call(s) } }
end
g = alt(*(0..2).map { |d| ->(s) { s } })
p g.call("5")
ps = (0..2).map { |d| ->(s) { s } }
h = alt(*ps)
p h.call("7")
