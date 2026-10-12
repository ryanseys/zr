# An ensure body runs on a normal exit, on an exception, and on a
# break, next or return that leaves through it. A def inside it defines
# the same method on each of those ways out, and the program builds.
def plain
  begin
    1
  ensure
    def from_plain = :plain
  end
end
plain
p from_plain

def raising
  begin
    raise "boom"
  ensure
    def from_raise(x = 1) = [:raise, x]
  end
rescue RuntimeError => e
  e.message
end
p raising
p from_raise(2)

def leaving
  [1, 2].each do |i|
    begin
      return i
    ensure
      def from_return = :return
    end
  end
end
p leaving
p from_return

r = [1, 2].each do
  begin
    break :broke
  ensure
    def from_break(&b) = b.call
  end
end
p r
p from_break { :block }

l = lambda do
  :lam
ensure
  def from_lambda = :lambda
end
p l.call
p from_lambda

begin
ensure
  class Made
    def made = :made
  end
  def with_block = [1, 2].map { |x| x * 3 }
  def self.single = :single
end
p Made.new.made
p with_block
p single

def counted
  @n = (@n || 0) + 1
end
3.times do
  begin
    next
  ensure
    def again = counted
  end
end
p again
p again
