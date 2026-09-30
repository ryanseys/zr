# A minor collection starts from what the last one kept and stops
# at every object it finds marked, so an old object that has come
# to hold a young one must be written down first, or the young one
# is swept from under it.
#
# `Array#[]=` has a path the compiler emits in place: where the
# receiver is an Array, the index a fixnum in range and the
# method its own, the element is written with no call at all. The
# kernel never sees that store, so the barrier it owes is the
# compiler's to emit beside it.
#
# The answers below are the same either way: a swept cell that
# nothing has taken yet still reads as what it held. What the
# missing barrier costs is not this program's answer but the next
# one's, so the run asks the collector itself -- ZR_GC_VERIFY holds
# every minor collection against a full trace and names the store
# that was not written down. ruby has no such variable and answers
# the three lines whatever the environment.

old = Array.new(1_000) { |i| [i] }
GC.start
GC.start
200_000.times { |i| old[i % 1_000] = [i, "row #{i}"] }
p old.size
p old.all? { |row| row.size == 2 }
p old[7].last
