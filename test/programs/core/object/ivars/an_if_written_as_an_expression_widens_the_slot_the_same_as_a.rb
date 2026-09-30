# A single-write ivar whose RHS is a ternary (or if-as-expression).
# The slot type comes from both branches. Branches of different
# concrete types widen the slot to poly, and each branch boxes its
# value. Branches of the same type give the slot that type.

# 6. if-as-expression form (statement-style) with mixed types.
#    Same AST shape (IfNode) as ternary, just multi-line surface syntax.
class C6
  def init(use_str)
    @x = if use_str
           "world"
         else
           99
         end
  end
  def show; puts @x; end
end

c6 = C6.new
c6.init(true);  c6.show              # world
c6.init(false); c6.show              # 99

