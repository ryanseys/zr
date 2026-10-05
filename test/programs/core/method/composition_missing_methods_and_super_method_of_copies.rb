# Method#<< follows the lambda flag of its argument. Methods that
# method_missing answers are equal only under one name. The super_method
# of a visibility copy or an alias starts after the original.
class Co
  def pow_2(x) = x * x
end
m = Co.new.method(:pow_2)
p((m << proc { |x| x + x }).lambda?, (m >> proc { |x| x }).lambda?, (m << m).lambda?, (m << proc { |x| x + x }).call(3))

class Mm
  def method_missing(n, *) = n.to_s.start_with?("h") ? 1 : super
  def respond_to_missing?(n, all = false) = n.to_s.start_with?("h") || super
end
mm = Mm.new
p mm.method(:ha) == mm.method(:ha), mm.method(:ha) == mm.method(:hb), mm.method(:ha).eql?(mm.method(:hb))

module SA
  private def derp(_m) = "A"
end

module SB
  private def derp = "B" + super(1)
end

class SC
  include SA
  include SB
  public :derp
  alias_method :meow, :derp
end
p SC.new.derp, SC.new.method(:derp).super_method.owner, SC.new.method(:meow).super_method.owner
p SC.instance_method(:derp).super_method.owner, SC.instance_method(:meow).super_method.owner
