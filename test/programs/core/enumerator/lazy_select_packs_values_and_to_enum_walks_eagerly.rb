# A lazy select or reject gets several yielded values as one Array, and a
# map gets the first. to_enum on a lazy walks with the eager method, and
# force passes its arguments to each.
class YM
  include Enumerable

  def each(arg = :d, *args)
    yield
    yield 0
    yield 0, 1
    yield 0, 1, 2
    yield nil
    yield arg
    yield args
    yield [0, 1]
  end
end
ys = []
YM.new.to_enum.lazy.select { |v| ys << v }.force
p ys
ys = []
YM.new.to_enum.lazy.reject { |v| ys << v; false }.force
p ys
p YM.new.to_enum.lazy.map { |v| v }.force
p YM.new.to_enum.lazy.force(:a1, :a2)
inf = (0..Float::INFINITY).lazy
p inf.to_enum(:with_index, 10).first(3)
p inf.enum_for(:each_slice, 2).map { |s| s.first * s.last }.first(4)
p (1..3).lazy.to_enum(:with_index, 10).to_a
