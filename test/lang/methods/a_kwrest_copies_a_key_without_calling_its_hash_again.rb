# `**rest` takes the keywords the method does not declare from a Hash
# whose keys already have their codes: ruby copies the entries, so a
# key's own `hash` runs once, at the call, and never for the rest.
class Key
  def initialize(limit) = @limit = limit
  def hash
    @limit -= 1
    raise "boom" if @limit < 0
    1
  end
  def eql?(other) = equal?(other)
end
def m(**rest) = rest.size
begin
  p m(Key.new(1) => 1)
rescue => e
  p [e.class, e.message]
end
def n(a: 0, **rest) = [a, rest.size]
p n(Key.new(1) => 2, a: 1)


__END__
1
[1, 1]
