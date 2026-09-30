module Tag; end
class A; end
class B < A; end
class C; include Tag; end
class D; end
class E; end
class F; end
class G < F; end

def kind(x)
  case x
  when B then "B"
  when A then "A"
  when Tag then "Tag"
  when D, E then "D or E"
  when F then "F"
  when Comparable then "Comparable"
  else "other"
  end
end

d = D.new
e = E.new
tagged = E.new
tagged.extend(Tag)
single = F.new
def single.hi = 1
subjects = [A.new, B.new, C.new, d, e, G.new, single, tagged, 1, "s", nil, true, :sym, 1.5, [], {}]
3.times do
  puts subjects.map { |s| kind(s) }.join(" ")
end
later = D.new
later.extend(Tag)
puts kind(later)
puts kind(d)
