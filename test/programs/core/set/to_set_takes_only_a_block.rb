# ruby 4.1 drops the deprecated arguments of to_set: Enumerable, Set and
# Range take none, only a block that maps each element.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

class MySet < Set; end

show { [[:e, Enumerable], [:s, Set], [:r, Range]].map { |n, m| [n, m.instance_method(:to_set).arity, m.instance_method(:to_set).parameters] } }
show { [3, 1, 2].to_set }
show { [3, 1, 2].to_set { |x| x * 10 } }
show { [1].to_set(Set) }
show { [1].to_set(MySet) }
show { (1..3).to_set }
show { (1..3).to_set { |x| -x } }
show { (1..3).to_set(Set) }
show { (1..).to_set }
show { {a: 1}.to_set }
show { [1, 2].each.to_set }

s = Set[1, 2]
show { s.to_set.equal?(s) }
show { s.to_set { |x| x }.equal?(s) }
show { s.to_set { |x| x + 1 } }
show { s.to_set(Set) }
m = MySet[1, 2]
show { [m.to_set.class, m.to_set.equal?(m)] }
show { m.to_set { |x| x * 2 } }
i = Set[1].compare_by_identity
show { i.to_set.compare_by_identity? }
