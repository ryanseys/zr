# A block handed to a method that FORWARDS it to a self-recursive yielder.
#
# The yielder recurses, so its block cannot be spliced into it -- it is lowered
# to take a real &block proc. The forwarder in front of it also yields. The
# block still writes to the enclosing locals themselves, not to a copy, so
# what it assigns arrives.
$ran = 0

def walk(n)
  yield
  walk(n - 1) { nil } if n > 0
  nil
end

def hop(n, &block)
  walk(n, &block)
end

seen = nil
hop(1) { $ran += 1; seen = 1 }
p [seen, $ran]

# Deeper: two forwarders in front of the yielder, and a capture written on
# every recursion level rather than once.
$log = []

def down(n)
  yield n
  down(n - 1) { |k| $log << -k } if n > 0
  nil
end

def mid(n, &b) = down(n, &b)
def top(n, &b) = mid(n, &b)

acc = []
top(2) { |k| acc << k }
p [acc, $log]

# The block written at the yielder's own call site was always right; pinned so
# the two paths cannot drift apart.
direct = []
walk(1) { direct << :d }
p direct

# The return type of a lowered recursive yielder is the one its body derives,
# not always Integer: a body can end in nil, a String or an Array.
def ends_nil(n)
  yield
  ends_nil(n - 1) { nil } if n > 0
  nil
end

def ends_str(n)
  yield
  ends_str(n - 1) { nil } if n > 0
  "x"
end

def ends_ary(n)
  yield
  ends_ary(n - 1) { nil } if n > 0
  [1]
end

def ends_sym(n)
  yield
  ends_sym(n - 1) { nil } if n > 0
  :a
end

p [ends_nil(1) { }, ends_str(1) { }, ends_ary(1) { }, ends_sym(1) { }]

# A return that DOES come out of a yield still reads the block's answer through
# the proc side-channel, which is what the forced Integer was there for.
def carry(n)
  return yield if n <= 0
  carry(n - 1) { yield }
end
p carry(2) { 42 }
