# A def that only spreads its `*rest` shares one frozen empty Array when no
# argument fills it. Each place that it spreads into still gets a new Array
# that it can change: a callee's rest, a literal, a super and a block. A def
# that keeps its rest gets a new one on each call.
def take(*a) = a
def collect(*a) = a << 1

def forward(*a) = take(*a)
def literal(*a) = [*a]
def into_collect(*a) = collect(*a)
def to_block(*a) = yield(*a)

x = forward
x << :mine
p x, x.frozen?
p forward, forward.equal?(forward)

y = literal
y << 2
p y, literal, literal.frozen?

p into_collect, into_collect
p(to_block { |*b| b << 3 })
p(to_block { |*b| b.frozen? })

class Base
  def run(*a) = a.push(:base)
end

class Child < Base
  def run(*a) = super
end

class Named < Base
  def run(*a) = super(*a)
end

p Child.new.run, Child.new.run.frozen?
p Named.new.run, Named.new.run

def kept(*a) = a
k = kept
k << 4
p k, kept, kept.equal?(kept), kept.frozen?

p forward(1, 2), literal(3), into_collect(5), Child.new.run(6)
p method(:forward).call, send(:literal), method(:into_collect).to_proc.call
