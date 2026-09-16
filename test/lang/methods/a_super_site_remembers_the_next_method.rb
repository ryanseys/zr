# A `super` site keeps the method it reached last, keyed on the chain
# node it runs from and the name; a redefinition, a new include, a
# define_method body shared under two names, a module met twice in
# the chain, a refinement and keywords all still reach ruby's answer.
class A; def hi(x, k: 1) = "A#{x}#{k}"; end
class B < A; def hi(x, k: 2) = "B" + super(x, k: k); end
class C < B; def hi(x, k: 3) = "C" + super; end
module M; def hi(x, k: 0) = "M" + super; end
class D < C; include M; def hi(x, k: 4) = "D" + super; end
objs = [B.new, C.new, D.new]
3.times { p objs.map { |o| o.hi(1) } }
class B; def hi(x, k: 2) = "b" + super(x, k: k); end
3.times { p objs.map { |o| o.hi(2) } }
class C; include M; end
3.times { p objs.map { |o| o.hi(3) } }
module N; def hi(x, k: 0) = "N" + super; end
D.prepend(N)
p D.new.hi(4), D.ancestors.take(5)
BODY = proc { |x| "dm:" + super(x) }
class E < A
  define_method(:hi, &BODY)
  define_method(:hey, &BODY)
  def hey(x) = "hey" + x.to_s
  alias_method :hey2, :hey
end
class F < E; define_method(:hey, &BODY); end
3.times { p [E.new.hi(5), F.new.hey(6)] }
class G < A
  def hi(x, k: 7) = [1].map { |i| super(x + i, k: k) }.first
  def with_block = super rescue $!.class
end
3.times { p G.new.hi(8), G.new.with_block }
module R
  refine(A) { def hi(x, k: 9) = "R" + super }
end
using R
3.times { p A.new.hi(10), D.new.hi(11) }
o = A.new
def o.hi(x, k: 12) = "S" + super
3.times { p o.hi(13) }
class H < A; def hi(x, k: 1) = super() rescue $!.class; end
p H.new.hi(1)
class I < A; def bye = super; end
p (I.new.bye rescue $!.class)


__END__
["BA12", "CBA13", "DMCBA14"]
["BA12", "CBA13", "DMCBA14"]
["BA12", "CBA13", "DMCBA14"]
["bA22", "CbA23", "DMCbA24"]
["bA22", "CbA23", "DMCbA24"]
["bA22", "CbA23", "DMCbA24"]
["bA32", "CMbA33", "DMCMbA34"]
["bA32", "CMbA33", "DMCMbA34"]
["bA32", "CMbA33", "DMCMbA34"]
"NDMCMbA40"
[N, D, M, C, M]
["dm:A51", "dm:hey6"]
["dm:A51", "dm:hey6"]
["dm:A51", "dm:hey6"]
"A97"
NoMethodError
"A97"
NoMethodError
"A97"
NoMethodError
"RA109"
"NDMCMbA110"
"RA109"
"NDMCMbA110"
"RA109"
"NDMCMbA110"
"SRA1312"
"SRA1312"
"SRA1312"
ArgumentError
NoMethodError
