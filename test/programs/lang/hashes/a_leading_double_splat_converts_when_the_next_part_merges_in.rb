# A hash literal or a call's keywords run each run of `k => v` pairs in
# full, then hash its keys. A leading `**x` converts only when the part
# after it merges in, so the values written after it run first. A `**nil`
# beside one other `**h` gives a copy of h that keeps its default.
$log = []
def log(x) = ($log << x; x)
def kw(*, **k) = k

class Key
  attr_reader :n

  def initialize(n) = @n = n
  def hash = ($log << "hash #{@n}"; @n.hash)
  def eql?(other) = other.is_a?(Key) && other.n == @n
  def inspect = "Key#{@n}"
end

class Pairs
  def to_hash = ($log << "to_hash"; { z: 26 })
end

bad = true
h = { a: 1 }
cases = {
  "**bad, s:" => -> { kw(**bad, s: log(2)) },
  "**bad, s:, u:" => -> { kw(**bad, s: log(2), u: log(3)) },
  "z:, **bad, k:" => -> { kw(z: log(1), **bad, k: log(3)) },
  "**h, **bad, k:" => -> { kw(**h, **bad, k: log(3)) },
  "**bad, **h" => -> { kw(**bad, **log(h)) },
  "**bad, k:, **h" => -> { kw(**bad, k: log(3), **log(h)) },
  "z:, **h, k:, **bad, m:" => -> { kw(z: log(1), **h, k: log(2), **bad, m: log(3)) },
  "{**bad, s:}" => -> { { **bad, s: log(2) } },
  "{**h, Key => v}" => -> { { **h, Key.new(1) => log(1), Key.new(2) => log(2) } },
  "{Key => v, Key => v}" => -> { { Key.new(1) => log(1), Key.new(2) => log(2) } },
  "{**Pairs, **h}" => -> { { **Pairs.new, **log(h) } },
  "{**h, **Pairs}" => -> { { **log(h), **Pairs.new } },
  "{**Pairs, k:}" => -> { { **Pairs.new, k: log(1) } },
  "{**bad, **h}" => -> { { **log(bad), **log(h) } },
}
cases.each do |label, code|
  $log.clear
  result = begin
    code.call
  rescue TypeError => e
    e.message
  end
  puts "#{label}: #{result.inspect} #{$log.inspect}"
end

with_default = Hash.new(5).merge(a: 1)
with_proc = Hash.new { |_, k| k }
identity = {}.compare_by_identity
p({ **with_default, **nil }.default)
p({ **nil, **with_default }.default)
p({ **with_default, b: 2 }.default)
p({ **with_proc, **nil }.default.class, { **with_proc, **nil }.default_proc)
p({ **with_proc }.default_proc.class)
p({ **identity, **nil }.compare_by_identity?)
p({ **nil, **identity }.compare_by_identity?)
p({ **identity, a: 1 }.compare_by_identity?)
p({ **nil, **nil })
p({ **nil, a: 1 })
