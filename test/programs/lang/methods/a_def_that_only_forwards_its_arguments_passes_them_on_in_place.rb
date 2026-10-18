# A def whose ... (or anonymous *, ** and &) only forwards keeps its
# arguments where its caller put them: each forwarding call passes the
# same values, keywords and block on, and a callee that keeps the
# keywords gets a copy of its own.
def target(*a, **k, &b) = [a, k, b&.call]
def fw(...) = target(...)
def fw1(x, ...) = target(x, :lead, ...)
def fw2(...) = (target(...); target(...))
def fwm(...) = [target(...), :after]
h = { a: 1 }
p fw, fw(1), fw(1, 2, k: 3), fw(**h), fw(1, **h) { :blk }, h
p fw1(9), fw1(9, 8, z: 1) { 2 }
p fw2(**h, q: 1), h
p fwm(1, *[2, 3], **{}, &-> { 4 })
def kw_only(a:, b: 2) = [a, b]
def fwk(...) = kw_only(...)
p fwk(a: 1), fwk(**h), (fwk(1) rescue $!.class)
def mut(**k) = (k[:m] = 1; k)
def fwm2(...) = [mut(...), mut(...)]
p fwm2(**h), h, fwm2(x: 1)
ruby2_keywords def r2(*a) = fw(*a)
p r2(1, k: 2)
def fwr(...) = fw(...)
p fwr(1, k: 2) { 5 }
p (fw1 rescue $!.message)
def fwe(...) = eval("target(...)")
p fwe(1, k: 1)
def fwb(...) = [1].map { target(...) }
p fwb(2, k: 2)
class A; def m(*a, **k) = [a, k]; end
class B < A; def m(...) = super(...); end
p B.new.m(1, k: 1)
def fws(...) = send(:target, ...)
p fws(1, k: 3)
def anon(*, **, &) = target(*, **, &)
p anon(1, k: 2) { 3 }
def lead2(a, b, ...) = target(b, a, ...)
p lead2(1, 2, 3, z: 4)
def fwh(...) = target(...)
big = (1..20).to_a
p fwh(*big, **{ y: 1 }).first.size
o = Object.new
def o.to_hash = { t: 1 }
p fw(**o)
