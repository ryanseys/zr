# The arity guard on calls the bare-call spec cannot reach: block-carrying
# calls (their accepted counts are probed separately -- `Array#fill` drops
# to 0..2 under a block), zero-arity readers, Struct member access, native
# instances, and receivers beyond the original eight.
#
# Three things this file was FILED for, all fixed. `String#bytesplice`
# accepted 2..3 where CRuby has four shapes up to five arguments -- the
# replacement's own byte window was simply missing. A Struct MEMBER
# accessor counted nothing, so `s.a(2)` answered the member and
# `s.send(:a=)` indexed an empty slice. And `1.step(nil)` read the explicit
# nil as a BOUND, so the first comparison failed on a NilClass the caller
# never wrote, where ruby's endless form runs.

require "stringio"

# review-found edges: an attribute named like an Object method is the
# attribute; empty splats are zero arguments; the iterator path type-checks
class Request
  attr_accessor :method, :path
  def initialize(m, p2) = (@method = m; @path = p2)
end
p Request.new("GET", "/").method
class Pt; attr_reader :x; def initialize = @x = 7; end
p Pt.new.x(*[])
begin
  3.step("a") { |i| i }
rescue ArgumentError => e
  p [e.class, e.message]
end
begin
  5.between?("a", "b")
rescue ArgumentError => e
  p [e.class, e.message]
end
p 1.step(nil) { |i| break :unbounded }
