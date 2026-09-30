class A; end
class B; end
class C; end
class D; end
class E; end
class F; end
KLASSES = Array.new(80) { |i| Class.new(i.even? ? A : B) }

def kind(x)
  case x
  when C then "C"
  when D then "D"
  when E then "E"
  when F then "F"
  when A then "A"
  when B then "B"
  else "else"
  end
end

counts = Hash.new(0)
4.times do |round|
  KLASSES.each { |k| counts[kind(k.new)] += 1 }
  [C, D, E, F].each { |k| counts[kind(k.new)] += 1 }
  GC.start
  tmp = Class.new(C)
  counts[kind(tmp.new)] += 1
  counts[kind(round)] += 1
end
p counts
