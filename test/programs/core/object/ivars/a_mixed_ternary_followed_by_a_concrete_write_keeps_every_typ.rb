# A single-write ivar whose RHS is a ternary (or if-as-expression).
# The slot type comes from both branches. Branches of different
# concrete types widen the slot to poly, and each branch boxes its
# value. Branches of the same type give the slot that type.

# 3. Mixed-type ternary combined with a later concrete write:
#    poly + concrete = stay poly.
class C3
  def init(use_str)
    @x = use_str ? "hello" : 42
  end
  def overwrite_sym
    @x = :sym
  end
  def show; puts @x; end
end

c3 = C3.new
c3.init(true);  c3.show              # hello
c3.overwrite_sym; c3.show            # sym
c3.init(false); c3.show              # 42

