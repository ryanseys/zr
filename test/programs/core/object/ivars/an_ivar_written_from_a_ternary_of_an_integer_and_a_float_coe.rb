# A single-write ivar whose RHS is a ternary (or if-as-expression).
# The slot type comes from both branches. Branches of different
# concrete types widen the slot to poly, and each branch boxes its
# value. Branches of the same type give the slot that type.

# 2. Same shape with Integer/Float -- neither value is coerced.
class C2
  def init(use_int)
    @x = use_int ? 100 : 1.5
  end
  def show; puts @x; end
end

c2 = C2.new
c2.init(true);  c2.show              # 100
c2.init(false); c2.show              # 1.5

