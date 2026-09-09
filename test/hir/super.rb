class A
  def hi(x, y = 2, *r, k: 1, &b)
    [:A, x, y, r, k, b ? b.call : nil]
  end
  def plain = :A_plain
  def blk = yield(:from_A)
end
class B < A
  def hi(x, y = 5, *r, k: 3, &b)
    r << :b
    super
  end
  def plain
    [super, super(), :B]
  end
  def blk = super { |v| [v, :B] }
  def blk2 = blk { |v| [v, :outer] }
  def nope = super
end
p B.new.hi(1), B.new.hi(1, 9, 8, k: 7) { :blk }
p B.new.plain, B.new.blk, B.new.blk2
begin
  B.new.nope
rescue NoMethodError => e
  puts e.message
  puts e.backtrace
end
module M
  def hi(*a) = [:M, super]
end
class C < B
  include M
  def hi(*a) = [:C, super(*a, k: 0)]
end
p C.new.hi(4)
class D < A
  def hi(x)
    [1, 2].map { |i| super(x + i) }
  end
end
p D.new.hi(10)
class E < A
  def hi(x)
    x = 99
    super
  end
end
p E.new.hi(1)
class F
  def self.make = [:F, self]
end
class G < F
  def self.make = [:G, super]
end
p G.make
