# A send written under `using` keeps cells like any other (SEND_USING):
# the refinements at a site are the site's own, so what the lookup
# answered under them is the class's and the stamp's at that site. A
# later `using`, a refinement defined later, and a redefinition of the
# method move the stamp; a send outside the file sees none of it, and
# a `new` under `using` reaches the refined initialize as ruby does.
class Foo; def hi = :plain; def bye = :plain_bye; end
module R
  refine Foo do
    def hi = :refined
    def extra = :extra
  end
end
def outside(f) = [f.hi, (f.extra rescue :none)]
using R
f = Foo.new
r = []
5.times { r << [f.hi, f.bye, f.extra, outside(f)] }
p r.uniq
p f.respond_to?(:extra), (f.send(:extra) rescue :nosend)
module R2
  refine Foo do
    def hi = :refined2
  end
end
using R2
p f.hi, outside(f)
class Foo; def hi = :redefined; end
p f.hi, outside(f)
p [1, 2].map { |x| f.hi }
def later(f) = f.hi
p later(f)
class Foo; def bye = :new_bye; end
p f.bye
class Bar; attr_reader :v; def initialize(v) = @v = v; end
module R3
  refine Bar do
    def initialize(v) = @v = v * 2
  end
end
using R3
p Bar.new(2).v, Bar.new(3).v
def make(v) = Bar.new(v)
p make(4).v
class Bar; def initialize(v) = @v = v + 100; end
p Bar.new(2).v, make(2).v
