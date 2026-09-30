# A single-write ivar whose RHS is a ternary (or if-as-expression).
# The slot type comes from both branches. Branches of different
# concrete types widen the slot to poly, and each branch boxes its
# value. Branches of the same type give the slot that type.

# 1. Ternary mixing String and Integer.
class C1
  def init(use_str)
    @x = use_str ? "hello" : 42
  end
  def show; puts @x; end
end

c1 = C1.new
c1.init(false); c1.show              # 42
c1.init(true);  c1.show              # hello

