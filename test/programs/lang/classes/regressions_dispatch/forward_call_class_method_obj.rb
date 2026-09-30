# `Class.new(obj)` shape: caller passes a user-class instance to a
# forward-defined Class.new. Mirrors the optcarrot
# `PPU.new(@conf, @cpu, @video.palette)` site, where the callee's
# param gets an object of a sibling class defined later.

class T_forward_call_class_method_obj_Holder
  def initialize(name)
    @name = name
  end
  def label
    "h:#{@name}"
  end
end

class T_forward_call_class_method_obj_Caller
  def make
    @h = T_forward_call_class_method_obj_Holder.new("alpha")
    @t = T_forward_call_class_method_obj_Target.new(@h)
  end
  def show
    @t.held_label
  end
end

class T_forward_call_class_method_obj_Target
  def initialize(h)
    @holder = h
  end
  def held_label
    @holder.label
  end
end

c = T_forward_call_class_method_obj_Caller.new
c.make
puts c.show
