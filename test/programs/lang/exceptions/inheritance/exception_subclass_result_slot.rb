# An exception subclass with ivars keeps StopIteration#result apart from its
# own ivars. A StopIteration subclass carrying an ivar reports nil #result,
# because it got no iteration value. A non-nil #result would mean `result`
# shares storage with @limit; 0 would mean `result` never got nil.
class BoundedStop < StopIteration
  def initialize(limit)
    super("stop")
    @limit = limit
  end
end

begin
  raise BoundedStop.new(7)
rescue StopIteration => e
  p e.result
end

# holds across repeated allocation churn (GC may scan live subclass exceptions)
ok = true
50.times do |i|
  begin
    raise BoundedStop.new(i)
  rescue StopIteration => e
    ok = false unless e.result.nil?
  end
end
p ok
