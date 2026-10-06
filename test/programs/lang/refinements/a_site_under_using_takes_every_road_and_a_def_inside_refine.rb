# A site under `using` takes the same roads as any site: the inline
# fixnum operator, the unary, the `[]`/`<<`/`push` entries, the cell,
# a block's `call`. Each road is guarded by a gate the runtime closes
# when a class redefines the name -- and a def inside `refine C`
# stands over C, so the gate closes at the definition and the site
# takes the call, which the refined lookup answers. The refinements
# stay told to the task for the callee, so `send`, `respond_to?`,
# `&:name` and `method` under `using` see them at a hot cell as ruby
# does; a site outside the file sees none of it.
module Arith
  refine Integer do
    def +(o) = [:plus, self, o]
    def succ = [:succ, self]
    def ==(o) = :eq
  end
  refine Array do
    def [](i) = [:aref, i]
    def <<(v) = [:shovel, v]
    def push(v) = [:push, v]
    def each = yield(:each)
  end
  refine String do
    def <<(v) = [:sh, v]
    def getbyte(i) = [:byte, i]
  end
  refine Proc do
    def call(*a) = [:called, *a]
  end
  refine Object do
    def hello = :hello
  end
end
def plain(a, s, pr) = [1 + 2, 3.succ, 1 == 1, a[0], a << 9, a.push(8), s << "x", s.getbyte(0), pr.call(4)]
using Arith
r = []
3.times do
  a = [7]
  s = +"q"
  pr = proc { |x| x }
  r.concat([[1 + 2, 3.succ, 1 == 1, a[0], a << 9, a.push(8), s << "x", s.getbyte(0), pr.call(4), 5.nil?]])
  [1].each { |x| r.concat([x]) }
end
p r.uniq
p plain([7], +"q", proc { |x| x })
o = Object.new
h = []
4.times { h.concat([[o.send(:hello), o.respond_to?(:hello), [o].map(&:hello), o.method(:hello).call, o.public_send(:hello)]]) }
p h.uniq
def take(&b) = b.call(1)
p take { |x| x }
