# A single-write ivar whose RHS is a ternary (or if-as-expression).
# The slot type comes from both branches. Branches of different
# concrete types widen the slot to poly, and each branch boxes its
# value. Branches of the same type give the slot that type.

# 7. Ternary with nil branch — should widen to nullable string,
#    not poly. Let the existing nullable widening flow through.
class C7
  def init(have)
    @x = have ? "yes" : nil
  end
  def show; puts @x.nil? ? "nope" : @x; end
end

c7 = C7.new
c7.init(true);  c7.show              # yes
c7.init(false); c7.show              # nope
