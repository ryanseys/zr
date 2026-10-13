# Enumerator::Lazy#zip converts its arguments with to_ary until one does
# not; that one and the rest must respond to each (ruby 4.1 keeps the
# converted ones). All Arrays are read by index, else each argument
# walks with to_enum, an Array subclass's own each too.
o = Object.new
def o.to_ary = [:a, :b]
z = (1..3).lazy.zip(o, 10..12)
p z.force, z.force
o2 = Object.new
def o2.to_ary = [:a, :b]
def o2.each; yield :c; yield :d; end
p (1..2).lazy.zip(o2, 10..11).force
p (1..3).lazy.zip(o).to_a
p (1..3).lazy.zip([4, 5], [6]).to_a
p (1..3).lazy.zip(10..11, [4, 5, 6, 7]).to_a
class MyArr < Array
  def each
    yield :x
    yield :y
  end
end
p (1..2).lazy.zip(MyArr[1, 2]).to_a
p (1..2).lazy.zip(5..6, MyArr[1, 2]).to_a
begin
  (1..2).lazy.zip(Object.new)
rescue TypeError => e
  p e.message
end
begin
  (1..2).lazy.zip(o, 3)
rescue TypeError => e
  p e.message
end
bad = Object.new
def bad.to_ary = 1
begin
  (1..2).lazy.zip(bad)
rescue TypeError => e
  p e.message
end
p (1..4).lazy.zip(o, 10..13).first(2)
p (1..3).lazy.zip(o).size
p (1..3).lazy.zip.to_a
r = []
p (1..2).lazy.zip([3, 4]) { |pair| r << pair }
p r
