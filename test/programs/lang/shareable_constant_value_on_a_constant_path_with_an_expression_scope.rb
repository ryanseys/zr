# shareable_constant_value: literal
# The magic comment applies to a write whose scope is an expression
# (`expr::C ||= v`, `&&=`, `+=` and `=`), as to any constant write.
B = Class.new
def self.expr = B
begin
  expr::C ||= ["Not " + "shareable"]
rescue Ractor::IsolationError => e
  p e.message
end
expr::D ||= ["a", "b"]
p B::D, B::D.frozen?, B::D.first.frozen?
begin
  expr::E &&= 1
rescue NameError => e
  p e.class
end
expr::F = ["x"]
p B::F.frozen?
expr::G = 1
expr::G += 2
p B::G
begin
  expr::H = [String.new("unshareable")]
rescue Ractor::IsolationError => e
  p e.message
end
