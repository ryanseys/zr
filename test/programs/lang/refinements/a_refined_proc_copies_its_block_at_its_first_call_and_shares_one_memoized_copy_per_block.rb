# Proc#refined copies the block at the refined Proc's first call, and
# keeps one copy for each block (proc_refined's memo). A miss warns in
# the performance category: other modules for the same block, a
# ruby2_keywords flag that changed after the copy, or a Proc whose block
# is already a copy.
module M1; refine(String) { def shout = "1" }; end
module M2; refine(String) { def shout = "2" }; end
Warning[:performance] = true
$warned = []
def Warning.warn(msg, category: nil) = $warned << [category, msg[/Proc#refined.*/]]
def warned = $warned.slice!(0..)

pr = ->(s) { s.shout }
p pr.refined(M1).call("hi"), warned
p pr.refined(M2).call("hi"), warned
p pr.refined(M2).call("hi"), warned
# Nothing is copied until a call, so making Procs warns about nothing.
pr.refined(M1)
pr.refined(M2)
p warned

# A copy of a copy is not memoized.
p1 = pr.refined(M1)
p1.refined(M2)
p warned
p p1.call("hi"), warned
p p1.refined(M2).call("hi"), warned

# The ruby2_keywords flag of the block, as the copy found it.
module M; refine(String) { def shout = upcase + "!" }; end
target = ->(a, k: nil) { [a, k] }
src = proc { |*args| target.call(*args) }
q1 = src.refined(M)
p((q1.call(1, k: 2) rescue $!.class))
src.ruby2_keywords
p src.call(1, k: 2)
q2 = src.refined(M)
p q2.call(1, k: 2), warned
p((q1.call(1, k: 2) rescue $!.class))
p src.refined(M).call(1, k: 2), warned

# A raise in a warning of the first call comes out of the call.
def Warning.warn(msg, category: nil) = raise "boom"
q = pr.refined(M1)
p((Fiber.new(&q).resume("hi") rescue $!.message))

# With the category off, nothing warns.
Warning[:performance] = false
def Warning.warn(msg, category: nil) = $warned << msg
p pr.refined(M2).call("hi"), pr.refined(M1).call("hi"), warned
