# Proc#ruby2_keywords on a Proc from Proc#refined marks that Proc alone:
# its keywords reach its rest as a flagged Hash, which a splat passes on
# as keywords. The source Proc and the other refined Procs of the same
# block keep their keywords apart. A Proc marked before Proc#refined
# gives its mark to the refined Procs that it makes.
$stderr = $stdout
module M
  refine(String) { def shout = upcase + "!" }
end
target = ->(a, k: nil) { [a, k] }
pr = proc { |*args| target.call(*args) }
q1 = pr.refined(M)
q2 = pr.refined(M)
p q1.ruby2_keywords.equal?(q1)
p q1.call(1, k: 2)
p q1.call(1)
# A Hash given as a Hash stays a positional argument.
begin
  q1.call(1, {k: 3})
rescue ArgumentError => e
  p [:hash_stays_positional, e.message]
end
[q2, pr].each do |other|
  other.call(1, k: 2)
rescue ArgumentError => e
  p [:argument_error, e.message]
end

# The refinements still apply in the marked Proc.
r = proc { |*a| [a.first.shout, *a.drop(1)] }.refined(M)
r.ruby2_keywords
p r.call("hi", k: 1)
p r.call("hi")

# Marked first, then refined.
pr2 = proc { |*args| target.call(*args) }
pr2.ruby2_keywords
p pr2.refined(M).call(3, k: 4)

# A refined Proc that takes keywords is not marked, with ruby's warning.
kp = proc { |a, k: 1| [a, k] }.refined(M)
kp.ruby2_keywords
p kp.call(5, k: 6)
