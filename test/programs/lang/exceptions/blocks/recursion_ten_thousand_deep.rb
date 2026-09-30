# Bounded recursion 10_000 deep -- plain, mutual, through a lambda, and on a
# spawned thread -- answers rather than raising. Past the stack limit,
# `SystemStackError` is rescuable.
#
# The lambda recurses by naming itself, so it holds the cell that holds it.
# At exit: cycle leak: 2 objects (Proc x1, cell x1)

def down(n) = n.zero? ? 0 : 1 + down(n - 1)
p down(10_000)

def ping(n) = n.zero? ? :ping : pong(n - 1)
def pong(n) = n.zero? ? :pong : ping(n - 1)
p ping(10_000)

count = nil
count = ->(n) { n.zero? ? 0 : 1 + count.(n - 1) }
p count.(10_000)

p Thread.new { down(10_000) }.value
