# A String or Symbol Range with an Integer step walks every member by
# succ and yields the begin, then every n-th member after it. A step of
# zero or less yields the begin alone, and the walk still runs to the end.
def walk(range, step)
  seen = []
  result = range.step(step) { |x| seen << x }
  [seen, result.equal?(range)]
end

p walk("a".."e", 2), walk("a"..."e", 3), walk("a".."e", 1)
p walk("a".."e", 0), walk("e".."a", -1), walk("a".."e", -2)
p walk(:a..:f, 2), walk(:a..:c, 0)
p walk("a"..."a", 1), walk("az".."bc", 2), walk("8".."12", 2)

seen = []
("a"..).step(3) { |x| seen << x; break if seen.size == 4 }
p seen

calls = 0
("a".."c").step(0) { |x| calls += 1 }
p calls
p ("a".."e").step(2).to_a, ("a".."e").step(0).to_a
