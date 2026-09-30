# A single-write ivar whose RHS is a ternary (or if-as-expression).
# The slot type comes from both branches. Branches of different
# concrete types widen the slot to poly, and each branch boxes its
# value. Branches of the same type give the slot that type.

# 5. Same-type-string ternary. Slot stays String.
class C5
  def init(loud)
    @x = loud ? "HEY" : "hi"
  end
  def show; puts @x; end
end

c5 = C5.new
c5.init(true);  c5.show              # HEY
c5.init(false); c5.show              # hi

