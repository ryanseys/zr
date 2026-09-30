# A single-write ivar whose RHS is a ternary (or if-as-expression).
# The slot type comes from both branches. Branches of different
# concrete types widen the slot to poly, and each branch boxes its
# value. Branches of the same type give the slot that type.

# 4. Same-type ternary. Both branches Integer, so the slot stays
#    Integer, with no boxing.
class C4
  def init(big)
    @x = big ? 1000 : 1
  end
  def show; puts @x; end
end

c4 = C4.new
c4.init(true);  c4.show              # 1000
c4.init(false); c4.show              # 1

