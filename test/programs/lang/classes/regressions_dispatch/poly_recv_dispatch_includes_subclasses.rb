# An ivar first holds a base class object, and a setter then stores a
# subclass object. A call on the ivar runs the subclass override. Tep
# uses this shape for `app.@before_filter.before(req, res)`.

class T_poly_recv_dispatch_includes_subclasses_Pipeline
  attr_accessor :step
  def initialize; @step = T_poly_recv_dispatch_includes_subclasses_Step.new; end
  def set_step(s); @step = s; end
  def run(out)
    @step.process(out)
  end
end

class T_poly_recv_dispatch_includes_subclasses_Step
  def process(out)
    out[:base] = "ran"
  end
end

class T_poly_recv_dispatch_includes_subclasses_UpcaseStep < T_poly_recv_dispatch_includes_subclasses_Step
  def process(out)
    out[:sub] = "UPPER"
  end
end

p = T_poly_recv_dispatch_includes_subclasses_Pipeline.new
p.set_step(T_poly_recv_dispatch_includes_subclasses_UpcaseStep.new)
result = { base: "" , sub: "" }
p.run(result)
puts result[:base]   # "" (base override not invoked)
puts result[:sub]    # "UPPER" (subclass override invoked)
