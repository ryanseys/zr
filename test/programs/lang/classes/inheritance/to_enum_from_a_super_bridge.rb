# `to_enum(:meth)` on the implicit self works correctly inside a
# method that a subclass reaches with `super`.
class Base
  def each
    return to_enum(:each) unless block_given?
    yield 1
    yield 2
  end

  def each_tagged(tag)
    return enum_for(:each_tagged, tag) unless block_given?
    yield "#{tag}-a"
    yield "#{tag}-b"
  end
end

class Sub < Base
  def each(&block)
    return to_enum(:each) unless block_given?
    super(&block)
    yield 3
  end
end

p Base.new.each.to_a
p Sub.new.each.to_a
p Base.new.each_tagged("x").to_a

collected = []
Sub.new.each { |n| collected << n }
p collected

e = Sub.new.each
p e.class
p e.next
p e.next
