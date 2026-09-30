# An `initialize` parameter gets a String from one Foo.new(...) call
# site and an Integer from another. Each object keeps its own value.

class T_initialize_param_poly_call_sites_Box
  def initialize(v)
    @v = v
  end

  def show
    puts @v
  end
end

T_initialize_param_poly_call_sites_Box.new("hello").show
T_initialize_param_poly_call_sites_Box.new(42).show
