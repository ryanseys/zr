# A def that only spreads its `**rest` shares one frozen empty Hash when no
# keyword fills it. Each place that it spreads into still gets a new Hash
# that it can change: a callee's keyword rest, a literal, a super and a
# block. A def that keeps its keyword rest gets a new one on each call.
def take(**k) = k
def change(**k) = k.merge!(x: 1)

def forward(**k) = take(**k)
def literal(**k) = { **k }
def into_change(**k) = change(**k)
def to_block(**k) = yield(**k)

h = forward
h[:mine] = 1
p h, h.frozen?
p forward, forward.equal?(forward)

l = literal
l[:y] = 2
p l, literal, literal.frozen?

p into_change, into_change
p(to_block { |**o| o[:q] = 1; o })
p(to_block { |**o| o.frozen? })

class Base
  def run(**k) = k.update(base: true)
end

class Child < Base
  def run(**k) = super
end

class Named < Base
  def run(**k) = super(**k)
end

p Child.new.run, Child.new.run.frozen?
p Named.new.run, Named.new.run

def kept(**k) = k
k = kept
k[:z] = 4
p k, kept, kept.equal?(kept), kept.frozen?

def positional(*a) = a
def to_positional(**k) = positional(**k)
p to_positional, to_positional(z: 1)

def gather(*a, **k) = [a, k]
def both(*a, **k) = gather(*a, **k)
p both, both(1), both(w: 2)
p forward(a: 1), literal(b: 2), into_change(c: 3), Child.new.run(d: 4)
p method(:forward).call, send(:literal), method(:into_change).to_proc.call
