
# A fused `arr.each` splice is guarded twice at run time -- the receiver's
# tag must be Array, and `zr_rt_iter_inline_ok_for` must still hold -- and
# the FALLBACK arm is what runs when either fails. That arm reaches the same
# epilogue as the inline one, so every slot the epilogue releases has to be
# initialised on it too.
#
# `Array.send(:define_method, :each)` is what makes the second guard answer
# false, so both arms run here in one program: the first call takes the
# inline arm, the second the fallback. The block parameter's slot must be
# initialised before the two arms split, so the second call does not
# release a slot that holds stack garbage.
#
# A RUN-TIME redefinition, deliberately. A compile-time `class Array; def
# each` reaches backwards and makes the FIRST call answer 30 as well. That
# is a separate gap, and this file must not depend on it.
#
# Runs under `ZR_TEST_RT_LEAKCHECK=1`, which is what makes it a memory-safety
# test rather than an output test.
#
# LIMIT: an uninitialised slot does not always make this program fail. The
# released bytes are stack garbage, and a short frame leaves benign garbage
# behind. What this file adds is coverage of the path, so a LOUD failure on
# it is caught.

def sum_of(a)
  total = 0
  a.each { |x| total += x }
  total
end

p sum_of([1, 2, 3])

Array.send(:define_method, :each) do |&b|
  b.call(10)
  b.call(20)
  self
end

p sum_of([1, 2, 3])
