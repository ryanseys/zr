# An unresolved constant on the rhs, stored into a hash with String values
# in VALUE position (the method tail). The NameError raise fires before the
# store.
class K
  def initialize = @h = { "x" => "y" }
  def put(k, v)
    @h[k] = Undef.compute(v)
  end
end
begin
  K.new.put("a", "b")
rescue NameError => e
  puts e.class
end
