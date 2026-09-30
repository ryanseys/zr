# A direct subclass of Set takes the compatibility layer that CRuby
# writes in Ruby, whose walks send each by name.
$calls = 0
module CountEach
  def each(*, &) = ($calls += 1; super)
end
[Array, Hash].each { |klass| klass.prepend(CountEach) }
class MySet < Set; end
set = MySet.new([1, 2])
counts = [$calls]
set.merge([3], { 4 => 5 })
counts << $calls
set & [1, 9]
counts << $calls
MySet.new([[1]]).flatten
counts << $calls
p counts, set.size
