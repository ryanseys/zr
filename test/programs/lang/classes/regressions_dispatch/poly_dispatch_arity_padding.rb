# Two user classes define `toggle` with different arities —
# T_poly_dispatch_arity_padding_Switch#toggle takes 0 args; T_poly_dispatch_arity_padding_Knob#toggle takes
# one positional default. A 0-arg call on each Switch works.

class T_poly_dispatch_arity_padding_Switch
  def initialize
    @v = 1
  end
  def toggle
    @v = 0
  end
  attr_reader :v
end

class T_poly_dispatch_arity_padding_Knob
  def toggle(soft = true)
    0
  end
end

class T_poly_dispatch_arity_padding_Box
  def initialize
    @items = [T_poly_dispatch_arity_padding_Switch.new, T_poly_dispatch_arity_padding_Switch.new]   # two classes
                                        # define `toggle`
  end
  attr_reader :items
end

b = T_poly_dispatch_arity_padding_Box.new
b.items[0].toggle
b.items[1].toggle
puts b.items[0].v   # 0
puts b.items[1].v   # 0
