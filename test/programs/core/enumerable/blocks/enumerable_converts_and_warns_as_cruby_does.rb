# Enumerable warns when a pattern leaves the block unused, converts with
# to_ary (flat_map, to_h), to_str (inject) and to_hash (tally, which
# ignores a default), and slice_before and slice_after take a pattern
# that is false or a block, not both.
def t
  yield
rescue => e
  [e.class, e.message]
end
e = [1, 2, 3].each_entry
p e.all?(Integer) { false }, e.any?(String) { true }, e.none?(String) { true }, e.one?(1) { false }, e.count(1) { true }, e.find_index(2) { false }
$VERBOSE = nil
p e.all?(Integer) { false }
$VERBOSE = false
ta = Object.new
def ta.to_ary = [8, 9]
tn = Object.new
def tn.to_ary = nil
bad = Object.new
def bad.to_ary = 5
p [1, 2].each_entry.flat_map { |x| x == 1 ? ta : x }, [1].each_entry.flat_map { tn }.size, t { [1].each_entry.flat_map { bad } }
op = Object.new
def op.to_str = "+"
p e.inject(op), e.inject(10, op), e.reduce(1, :*) { 0 }
h = Hash.new(100)
p %w[a b a].each_entry.tally(h)
ho = Object.new
def ho.to_hash = @h ||= {}
p %w[a b a].each_entry.tally(ho)
pr = Object.new
def pr.to_ary = [:k, :v]
p [pr].each_entry.to_h, [1].each_entry.to_h { pr }
p [7, 6, 5, 4, 3, 2, 1].each_entry.slice_before(&:even?).to_a, [7, 6, 5, 4].each_entry.slice_before(false).to_a, [7, 6, 5].each_entry.slice_before(6).to_a
p t { e.slice_before(1) { } }, t { e.slice_after(1) { } }
