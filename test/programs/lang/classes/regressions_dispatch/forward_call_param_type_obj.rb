# Forward-call with a user-class-typed arg flowing through the
# caller's ivar to the callee's parameter slot. Mirrors optcarrot's
# `@ppu.nametables = @mirroring` shape — the callee accepts an
# object of a user class, and the call goes through the `@target`
# ivar.

class T_forward_call_param_type_obj_Holder
  def initialize(name)
    @name = name
  end
  def label
    "h:#{@name}"
  end
end

class T_forward_call_param_type_obj_Caller
  def initialize(target)
    @target = target
    @holder = T_forward_call_param_type_obj_Holder.new("alpha")
  end
  def go
    @target.attach(@holder)
  end
end

class T_forward_call_param_type_obj_Target
  def attach(h)
    @holder = h
  end
  def held_label
    @holder.label
  end
end

t = T_forward_call_param_type_obj_Target.new
c = T_forward_call_param_type_obj_Caller.new(t)
c.go
puts t.held_label
