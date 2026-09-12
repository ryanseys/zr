# CRITICAL bug, found via the operator-method test above (`@x * @x`
# inside `Vector#<=>`): the old emitter's `IvarRead` and
# captured-`LocalRead` lowerings both emitted a bare, UNNAMED
# `#expr.lock().clone()`. An unnamed lock guard stays alive until the end
# of the ENCLOSING STATEMENT, so referencing the SAME ivar or captured
# local TWICE in one expression/statement (a very common shape: squaring,
# self-comparison, `total - total`, not just the already-audited
# read-modify-WRITE case) silently deadlocked the whole generated program
# forever -- no abort, no error, just a permanent hang. Fixed by binding
# the guard to an explicit named local INSIDE its own block (confirmed
# empirically that a bare `{ }` wrapper alone does NOT change the release
# timing -- only a named binding does).

class Squarer
  def initialize(n)
    @n = n
  end
  def square
    @n * @n
  end
end
puts Squarer.new(7).square

class Once
  def run
    yield
  end
end
total = 5
block_result = 0
Once.new.run { block_result = total * total }
puts block_result
__END__
49
25
