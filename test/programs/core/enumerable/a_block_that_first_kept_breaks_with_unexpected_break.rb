# Enumerable#first leaves each with a break, as first_i calls
# rb_iter_break, so a call of its block after first ends raises
# "unexpected break" (test_enum.rb's test_first). A program's own proc
# that breaks after its call ends raises "break from proc-closure".
empty = Object.new
class << empty
  attr_reader :block
  include Enumerable
  def each(&block)
    @block = block
    self
  end
end
p empty.first, [3, 4].each_slice(1).first, (1..Float::INFINITY).first, { a: 1 }.first
begin
  empty.block.call
rescue LocalJumpError => e
  p e.message, e.reason
end
def keep(&b) = b
pr = keep { break 5 }
begin
  pr.call
rescue LocalJumpError => e
  p e.message
end
