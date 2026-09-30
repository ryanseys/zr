class Even
  def ===(o) = o.is_a?(Integer) && o.even?
end
SMALL = 1..3
EVEN = Even.new
class A; end
class B; end
class C; end
class D; end

def kind(x)
  case x
  when A then "A"
  when SMALL then "small"
  when EVEN then "even"
  when B, C then "B or C"
  when D then "D"
  else "else"
  end
end

3.times do
  puts [A.new, 2, 3, 4, 5, B.new, C.new, D.new, "x", nil].map { |x| kind(x) }.join(" ")
end
