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

# native-class instances and Mutex check their probed rows
begin
  p(StringIO.new("x").eof?(1))
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end
begin
  p(Mutex.new.synchronize(1) { 2 })
rescue TypeError, ArgumentError => e
  p [e.class, e.message]
end

