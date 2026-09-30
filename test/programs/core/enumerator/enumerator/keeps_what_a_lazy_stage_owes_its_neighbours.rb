# map, select, reject and filter_map go through the kernel's
# adapter (zr_lazy_stage) rather than a `|*values|` block, which
# allocated that Array once an element and once a stage. These
# are what the adapter owes: the block sees the values unpacked,
# what a stage sends on is the element packed, and the block is
# called after the call that took it has returned.
class Several
  include Enumerable
  def each
    yield 1, 2
    yield 3
    yield
    yield 4, 5, 6
    self
  end
end

p Several.new.lazy.map { |a| a }.force
p Several.new.lazy.map { |a, b| [a, b] }.force
p Several.new.lazy.select { true }.force
p Several.new.lazy.reject { false }.force
p Several.new.lazy.filter_map { |a| a }.force

# A `break` in a lazy block has nothing to break out of.
begin
  (1..5).lazy.map { |x| break :broke if x == 3; x }.force
rescue LocalJumpError => e
  p [e.reason, e.message]
end

# A lambda is held to its arity where an ordinary block is not.
begin
  { a: 1 }.lazy.map(&->(a, b) { a }).force
rescue ArgumentError => e
  p e.message
end
p({ a: 1, b: 2 }.lazy.map { |k| k }.force)

# nil and false are what filter_map drops and map keeps.
p (1..3).lazy.filter_map { |x| x.odd? && x }.force
p (1..3).lazy.map { |x| nil }.force

# The walk stops where the consumer stops, endlessly.
p (1..Float::INFINITY).lazy.map { |x| x * 3 }.select(&:even?).first(4)
