#@ skip: a continuation does not survive a collection: the program aborts on SIGABRT
# A continuation keeps the frames it saved alive across collections, a
# loop can be made of one, and a call from another fiber or thread is
# refused.
$stderr.reopen(IO::NULL)
require "continuation"
# A continuation holds the frames it saved alive across collections.
def collect
  strings = (1..50).map { |i| "s#{i}" * 3 }
  k = callcc { |c| c }
  if k.is_a?(Continuation)
    100.times { "garbage" * 100 }
    GC.start
    [k, strings.size]
  else
    [nil, strings.map(&:size).sum, k]
  end
end
k, n = collect
p n
if k
  GC.start
  k.call(:back)
end
# A loop made of a continuation.
i = 0
top = callcc { |c| c }
i += 1
top.call(top) if i < 1000
p i
# Across fibers and threads.
saved = callcc { |c| c }
if saved.is_a?(Continuation)
  p((Fiber.new { saved.call(1) }.resume rescue $!))
  p((Thread.new { saved.call(1) }.value rescue $!))
end
p Continuation.respond_to?(:new), [].respond_to?(:callcc, true)

__END__
50
423
1000
#<RuntimeError: continuation called across fiber>
#<RuntimeError: continuation called across threads>
false
true
