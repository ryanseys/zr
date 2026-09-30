class T_nil_scalar_ivar_widen_HitState
  def initialize
    @material_index = nil
  end

  def hit!(idx)
    @material_index = idx
  end

  def label
    @material_index.nil? ? "miss" : "hit"
  end
end

state = T_nil_scalar_ivar_widen_HitState.new
puts state.label
state.hit!(0)
puts state.label

class T_nil_scalar_ivar_widen_ResetState
  def initialize
    @material_index = 0
  end

  def clear!
    @material_index = nil
  end

  def label
    @material_index.nil? ? "miss" : "hit"
  end
end

reset = T_nil_scalar_ivar_widen_ResetState.new
puts reset.label
reset.clear!
puts reset.label

class T_nil_scalar_ivar_widen_ParamResetState
  def initialize
    @material_index = 0
  end

  def set(idx)
    @material_index = idx
  end

  def label
    @material_index.nil? ? "miss" : "hit"
  end
end

param_reset = T_nil_scalar_ivar_widen_ParamResetState.new
puts param_reset.label
param_reset.set(nil)
puts param_reset.label
