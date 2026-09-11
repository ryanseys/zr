# An operator assignment through a literal `self` may call private
# readers, writers, `[]` and `[]=`, as a plain `self.x = v` may.
class Counter
  def bump = (self.count += 1; count)
  def seed = (self.count ||= 5; count)
  def slot = (self[0] ||= :v; self[0])
  def add = (self[1] += 2; self[1])

  private

  attr_accessor :count

  def [](i) = @h[i]

  def []=(i, v)
    @h[i] = v
  end

  def initialize
    @count = 1
    @h = {1 => 1}
  end
end
c = Counter.new
p c.bump, Counter.new.seed, c.slot, c.add
begin
  c.count += 1
rescue NoMethodError => e
  p e.message
end

__END__
2
1
:v
3
"private method 'count' called for an instance of Counter"
