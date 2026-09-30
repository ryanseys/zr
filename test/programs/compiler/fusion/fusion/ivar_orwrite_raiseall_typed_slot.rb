# `@x ||= recv.map { ... }` where recv is nil, so the RHS can only raise.
# @x holds an Array from another assignment. The or-write raises
# NoMethodError at run time like CRuby.
class Store
  def taggings; @data; end
  def seed(d); @memo = d; end
  def compute
    @memo ||= taggings.reject { |x| false }.map { |x| x }
  end
end
s = Store.new
begin
  p s.compute
rescue NoMethodError => e
  p e.class
end
s2 = Store.new
s2.seed([10, 20])
p s2.compute
