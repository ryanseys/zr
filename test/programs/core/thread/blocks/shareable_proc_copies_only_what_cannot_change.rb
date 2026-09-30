# `Ractor.shareable_proc` copies the outer locals its block reads, so it
# holds only locals that cannot change: each one bound once in its own
# scope, and holding a shareable value. It refuses a block that writes an
# outer local, and one whose self is not shareable; the Proc it answers is
# frozen, and no Binding reaches its scope.
def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end

def param(name) = Ractor.shareable_proc { name }
try("a parameter") { [param(:x).call, param(:x).frozen?, Ractor.shareable?(param(:x))] }

def assigned_once
  v = :once
  Ractor.shareable_proc { v }
end
try("bound once") { assigned_once.call }

def assigned_twice
  v = :a
  v = :b
  Ractor.shareable_proc { v }
end
try("bound twice") { assigned_twice }

def assigned_after
  v = :a
  pr = Ractor.shareable_proc { v }
  v = :b
  pr
end
try("bound again after") { assigned_after }

def param_then_assigned(v)
  v = 1
  Ractor.shareable_proc { v }
end
try("a parameter bound again") { param_then_assigned(0) }

def in_a_loop
  i = 0
  while i < 1
    v = 5
    i += 1
  end
  Ractor.shareable_proc { v }
end
try("bound once in a loop") { in_a_loop.call }

def two_arms(c)
  if c then v = 1 else v = 2 end
  Ractor.shareable_proc { v }
end
try("bound in two arms") { two_arms(true) }

def another_block_writes
  v = 1
  [1].each { v = 2 }
  Ractor.shareable_proc { v }
end
try("written by another block") { another_block_writes }

def named_group
  /(?<w>a)/ =~ "a"
  Ractor.shareable_proc { w }
end
try("a named group") { named_group }

def unshareable
  v = []
  Ractor.shareable_proc { v }
end
try("an unshareable value") { unshareable }

def frozen_array
  v = [1, 2].freeze
  Ractor.shareable_proc { v }.call
end
try("a frozen array") { frozen_array }

def writes_inside
  v = 1
  Ractor.shareable_proc { v = 2 }
end
try("writes an outer local") { writes_inside }

def writes_nested
  a = 1
  Ractor.shareable_proc { [1].each { a = 2 } }
end
try("a nested block writes it") { writes_nested }

def writes_two
  zeta = 1
  alpha = 1
  Ractor.shareable_proc { alpha = 2; zeta = 3 }
end
try("writes two") { writes_two }

def both_rebound
  zeta = 1
  zeta = 2
  alpha = 1
  alpha = 2
  Ractor.shareable_proc { [zeta, alpha] }
end
try("two bound twice") { both_rebound }

def mixed
  alpha = []
  zeta = 1
  zeta = 2
  Ractor.shareable_proc { [alpha, zeta] }
end
try("one unshareable, one bound twice") { mixed }

try("self by default") { Ractor.shareable_proc { self }.call }
try("self: 5") { Ractor.shareable_proc(self: 5) { self }.call }
try("self: []") { Ractor.shareable_proc(self: []) { self } }
try("an unknown keyword") { Ractor.shareable_proc(foo: 1) { } }
try("no block") { Ractor.shareable_proc }

def lam(name) = Ractor.shareable_lambda { name }
try("a lambda") { [lam(:q).lambda?, lam(:q).call] }
pr = proc { 1 }
try("a passed proc") { s = Ractor.shareable_proc(&pr); [s.equal?(pr), pr.frozen?, s.frozen?, s.lambda?] }
try("a passed proc to shareable_lambda") { Ractor.shareable_lambda(&pr).lambda? }

class Table
  def initialize = @t = { a: 1 }
end
def getter(name) = Ractor.shareable_proc { @t[name] }
t = Table.new
t.define_singleton_method(:a, &getter(:a))
try("as a method") { t.a }

def nested(n) = Ractor.shareable_proc { [1].map { n } }
try("read by a nested block") { nested(3).call }
def two_out(n) = [1].map { Ractor.shareable_proc { n } }.first
try("two scopes out") { two_out(4).call }
def each_made = [1, 2].map { |i| Ractor.shareable_proc { i } }.map(&:call)
try("one a block call") { each_made }

def copies(n)
  pr = Ractor.shareable_proc { n }
  [pr.dup.frozen?, pr.clone.frozen?]
end
try("dup and clone") { copies(1) }
try("binding") { Ractor.shareable_proc { }.binding }
try("dup's binding") { Ractor.shareable_proc { }.dup.binding.class }

